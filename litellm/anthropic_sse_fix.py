import copy
import json
from typing import Any, AsyncGenerator, Optional

from litellm.integrations.custom_logger import CustomLogger
from litellm import verbose_logger


class AnthropicDeepSeekAdapter(CustomLogger):
    _DUMMY_SIGNATURE = "EqQBCgIYAhIM1gbcDa9GJwZA2b3hGgxBdjrkzLoky3dl1pkiMOYdsBjCFLxFhxaGMpTIjOCjk"

    def _should_activate(self, request_data: dict) -> bool:
        if not self._is_messages_route(request_data):
            return False
        metadata = request_data.get("litellm_metadata") or {}
        model_info = metadata.get("model_info") or {}
        litellm_model = model_info.get("key") or metadata.get("deployment_model_name") or ""
        verbose_logger.info(
            "AnthropicDeepSeekAdapter litellm_model=%s model_group=%s model=%s",
            litellm_model,
            metadata.get("model_group") or "",
            request_data.get("model"),
        )
        return "deepseek" in litellm_model

    def _is_messages_route(self, request_data: dict) -> bool:
        metadata = request_data.get("litellm_metadata") or {}
        route_candidates = [
            request_data.get("route"),
            request_data.get("request_route"),
            metadata.get("user_api_key_request_route"),
            metadata.get("endpoint"),
        ]

        requester_metadata = metadata.get("requester_metadata") or {}
        route_candidates.extend(
            [
                requester_metadata.get("path"),
                requester_metadata.get("request_path"),
            ]
        )

        for route in route_candidates:
            if isinstance(route, str) and (
                route == "anthropic_messages" or "/v1/messages" in route
            ):
                return True

        return False

    def _is_empty_text_delta(self, chunk: dict) -> bool:
        return (
            chunk.get("type") == "content_block_delta"
            and (chunk.get("delta") or {}).get("type") == "text_delta"
            and not (chunk.get("delta") or {}).get("text")
        )

    def _parse_sse_chunk(self, item: Any) -> Optional[tuple[str, dict]]:
        if not isinstance(item, (bytes, bytearray)):
            return None

        text = bytes(item).decode("utf-8", errors="replace")
        event_type: Optional[str] = None
        data_lines: list[str] = []

        for line in text.splitlines():
            if line.startswith("event: "):
                event_type = line[len("event: ") :]
            elif line.startswith("data: "):
                data_lines.append(line[len("data: ") :])

        if event_type is None or not data_lines:
            return None

        try:
            payload = json.loads("\n".join(data_lines))
        except json.JSONDecodeError:
            return None

        if not isinstance(payload, dict):
            return None

        return event_type, payload

    def _encode_sse_chunk(self, event_type: str, payload: dict) -> bytes:
        return (
            f"event: {event_type}\ndata: {json.dumps(payload, ensure_ascii=False)}\n\n"
        ).encode()

    def _normalized_start_chunk(
        self,
        source: Optional[dict],
        block_type: str,
        index: int,
    ) -> dict:
        chunk = copy.deepcopy(source) if source is not None else {"type": "content_block_start"}
        chunk["type"] = "content_block_start"
        chunk["index"] = index

        content_block = (chunk.get("content_block") or {}) if isinstance(chunk, dict) else {}
        if block_type == "thinking":
            thinking_block = {"type": "thinking", "thinking": ""}
            signature = content_block.get("signature") or self._DUMMY_SIGNATURE
            thinking_block["signature"] = signature
            chunk["content_block"] = thinking_block
        elif block_type == "tool_use":
            if content_block.get("type") == "tool_use":
                chunk["content_block"] = content_block
            else:
                chunk["content_block"] = {
                    "type": "tool_use",
                    "id": content_block.get("id", ""),
                    "name": content_block.get("name", ""),
                    "input": content_block.get("input", {}),
                }
        else:
            chunk["content_block"] = {"type": "text", "text": ""}

        return chunk

    def _stop_chunk(self, index: int) -> dict:
        return {"type": "content_block_stop", "index": index}

    def _maybe_emit_signature_delta(
        self,
        active_block_type: Optional[str],
        active_index: Optional[int],
    ) -> list[bytes]:
        if active_block_type == "thinking" and active_index is not None:
            return [
                self._encode_sse_chunk(
                    "content_block_delta",
                    {
                        "type": "content_block_delta",
                        "index": active_index,
                        "delta": {
                            "type": "signature_delta",
                            "signature": self._DUMMY_SIGNATURE,
                        },
                    },
                )
            ]
        return []

    def _delta_kind(self, chunk: dict) -> Optional[str]:
        if chunk.get("type") != "content_block_delta":
            return None
        return (chunk.get("delta") or {}).get("type")

    async def async_pre_call_hook(
        self,
        user_api_key_dict: Any,
        cache: Any,
        data: dict,
        call_type: str,
    ) -> Optional[dict]:
        if call_type != "acompletion" or not self._should_activate(data):
            return data

        if "thinking" in data:
            data = copy.deepcopy(data)
            data.pop("thinking", None)

        return data

    async def async_post_call_streaming_iterator_hook(
        self,
        user_api_key_dict: Any,
        response: Any,
        request_data: dict,
    ) -> AsyncGenerator[Any, None]:
        if not self._should_activate(request_data):
            async for item in response:
                yield item
            return

        requested_model = request_data.get("model")
        pending_start: Optional[dict] = None
        active_block_type: Optional[str] = None
        active_index: Optional[int] = None
        next_index = 0

        async for item in response:
            parsed_chunk = self._parse_sse_chunk(item)
            if parsed_chunk is None:
                yield item
                continue

            event_type, chunk = parsed_chunk
            chunk_type = chunk.get("type")

            if chunk_type == "message_start" and event_type == "message_start":
                message = chunk.get("message") or {}
                if isinstance(message, dict) and isinstance(requested_model, str):
                    message["model"] = requested_model
                yield self._encode_sse_chunk(event_type, chunk)
                continue

            if chunk_type == "content_block_start" and event_type == "content_block_start":
                pending_start = chunk
                continue

            if chunk_type == "content_block_stop" and event_type == "content_block_stop":
                pending_start = None
                if active_index is not None:
                    for sse_event in self._maybe_emit_signature_delta(
                        active_block_type,
                        active_index,
                    ):
                        yield sse_event
                    yield self._encode_sse_chunk(
                        "content_block_stop", self._stop_chunk(active_index)
                    )
                    active_block_type = None
                    active_index = None
                continue

            if chunk_type == "content_block_delta" and event_type == "content_block_delta":
                delta_kind = self._delta_kind(chunk)
                desired_block_type = None
                if delta_kind in {"thinking_delta", "signature_delta"}:
                    desired_block_type = "thinking"
                elif delta_kind == "text_delta":
                    if self._is_empty_text_delta(chunk):
                        continue
                    desired_block_type = "text"
                elif delta_kind == "input_json_delta":
                    desired_block_type = "tool_use"

                if active_block_type is None and desired_block_type is not None:
                    start_chunk = self._normalized_start_chunk(
                        source=pending_start,
                        block_type=desired_block_type,
                        index=next_index,
                    )
                    active_block_type = desired_block_type
                    active_index = next_index
                    next_index += 1
                    pending_start = None
                    yield self._encode_sse_chunk("content_block_start", start_chunk)
                elif (
                    desired_block_type is not None
                    and active_block_type is not None
                    and desired_block_type != active_block_type
                    and active_index is not None
                ):
                    for sse_event in self._maybe_emit_signature_delta(
                        active_block_type,
                        active_index,
                    ):
                        yield sse_event
                    yield self._encode_sse_chunk(
                        "content_block_stop", self._stop_chunk(active_index)
                    )
                    start_chunk = self._normalized_start_chunk(
                        source=pending_start,
                        block_type=desired_block_type,
                        index=next_index,
                    )
                    active_block_type = desired_block_type
                    active_index = next_index
                    next_index += 1
                    pending_start = None
                    yield self._encode_sse_chunk("content_block_start", start_chunk)
                elif pending_start is not None:
                    pending_start = None

                if active_index is not None:
                    chunk["index"] = active_index
                yield self._encode_sse_chunk("content_block_delta", chunk)
                continue

            if chunk_type == "message_delta" and event_type == "message_delta":
                pending_start = None
                if active_index is not None:
                    for sse_event in self._maybe_emit_signature_delta(
                        active_block_type,
                        active_index,
                    ):
                        yield sse_event
                    yield self._encode_sse_chunk(
                        "content_block_stop", self._stop_chunk(active_index)
                    )
                    active_block_type = None
                    active_index = None
                yield self._encode_sse_chunk(event_type, chunk)
                continue

            pending_start = None
            yield self._encode_sse_chunk(event_type, chunk)

        if active_index is not None:
            for sse_event in self._maybe_emit_signature_delta(
                active_block_type,
                active_index,
            ):
                yield sse_event
            yield self._encode_sse_chunk(
                "content_block_stop", self._stop_chunk(active_index)
            )


proxy_handler_instance = AnthropicDeepSeekAdapter()
