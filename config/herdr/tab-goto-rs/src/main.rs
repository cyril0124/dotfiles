//! Tab-only herdr goto, Rust port of the Python/curses picker.
//! One binary, two modes: `open` (popup launcher) and `picker` (default, TUI).

use std::collections::HashSet;
use std::io::{self, IsTerminal, Write};
use std::os::unix::process::CommandExt;
use std::process::Command;

use crossterm::{
    cursor::{Hide, MoveTo, Show},
    event::{
        DisableMouseCapture, EnableMouseCapture, Event, KeyCode, KeyEventKind, KeyModifiers,
        MouseButton, MouseEventKind,
    },
    execute, queue,
    style::{Attribute, Color, Print, ResetColor, SetAttribute, SetBackgroundColor, SetForegroundColor},
    terminal::{self, Clear, ClearType, EnterAlternateScreen, LeaveAlternateScreen},
};
use serde_json::Value;

// ---------- herdr access ----------

fn herdr_bin() -> Result<String, String> {
    if let Ok(path) = std::env::var("HERDR_BIN_PATH") {
        if !path.is_empty() && is_executable(&path) {
            return Ok(path);
        }
    }
    let paths = std::env::var("PATH").unwrap_or_default();
    for dir in paths.split(':') {
        let cand = format!("{dir}/herdr");
        if is_executable(&cand) {
            return Ok(cand);
        }
    }
    Err("herdr not found (set HERDR_BIN_PATH or PATH)".into())
}

fn is_executable(path: &str) -> bool {
    use std::os::unix::fs::PermissionsExt;
    std::fs::metadata(path)
        .map(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
        .unwrap_or(false)
}

fn herdr_json(bin: &str, args: &[&str]) -> Result<Value, String> {
    let out = Command::new(bin)
        .args(args)
        .stderr(std::process::Stdio::null())
        .output()
        .map_err(|e| format!("herdr {}: {e}", args.join(" ")))?;
    if !out.status.success() {
        return Err(format!("herdr {} failed", args.join(" ")));
    }
    let payload: Value = serde_json::from_slice(&out.stdout)
        .map_err(|e| format!("herdr {}: bad json: {e}", args.join(" ")))?;
    match payload.get("result") {
        Some(r) if r.is_object() => Ok(r.clone()),
        _ => Ok(payload),
    }
}

// ---------- data ----------

#[derive(Clone)]
struct Row {
    tab_id: String,
    workspace_id: String,
    workspace: String,
    tab: String,
    status: String,
    focused: bool,
}

fn json_str(v: &Value, key: &str) -> Option<String> {
    v.get(key).and_then(|x| x.as_str()).map(|s| s.to_string())
}

fn load_workspaces(bin: &str) -> std::collections::HashMap<String, String> {
    let mut workspaces = std::collections::HashMap::new();
    if let Ok(ws_result) = herdr_json(bin, &["workspace", "list"]) {
        if let Some(list) = ws_result.get("workspaces").and_then(|w| w.as_array()) {
            for ws in list {
                if let Some(wid) = json_str(ws, "workspace_id").filter(|s| !s.is_empty()) {
                    let label = json_str(ws, "label").filter(|s| !s.is_empty()).unwrap_or_else(|| wid.clone());
                    workspaces.insert(wid, label);
                }
            }
        }
    }
    workspaces
}

fn load_tabs(bin: &str) -> Result<Vec<Row>, String> {
    let tab_result = herdr_json(bin, &["tab", "list"])?;
    let tabs = match tab_result.get("tabs").and_then(|t| t.as_array()) {
        Some(t) if !t.is_empty() => t.clone(),
        _ => return Ok(vec![]),
    };
    let workspaces = load_workspaces(bin);

    let mut rows = Vec::new();
    for tab in &tabs {
        let tid = match json_str(tab, "tab_id").filter(|s| !s.is_empty()) {
            Some(t) => t,
            None => continue,
        };
        let wid = json_str(tab, "workspace_id").unwrap_or_else(|| "?".into());
        let wlabel = workspaces.get(&wid).cloned().unwrap_or_else(|| wid.clone());
        let tlabel = json_str(tab, "label").filter(|s| !s.is_empty()).unwrap_or_else(|| tid.clone());
        let status = json_str(tab, "agent_status").unwrap_or_default();
        let focused = tab.get("focused").and_then(|f| f.as_bool()).unwrap_or(false);
        rows.push(Row {
            tab_id: tid,
            workspace_id: wid,
            workspace: wlabel,
            tab: tlabel,
            status,
            focused,
        });
    }
    Ok(rows)
}

fn initial_index(rows: &[Row]) -> usize {
    rows.iter().position(|r| r.focused).unwrap_or(0)
}

// ---------- last-tab state ----------

fn state_dir() -> std::path::PathBuf {
    if let Ok(env) = std::env::var("HERDR_PLUGIN_STATE_DIR") {
        if !env.is_empty() {
            return env.into();
        }
    }
    std::env::current_dir().unwrap_or_else(|_| ".".into()).join(".state")
}

fn read_last_tab() -> Option<String> {
    let text = std::fs::read_to_string(state_dir().join("last-tab")).ok()?;
    let text = text.trim().to_string();
    (!text.is_empty()).then_some(text)
}

fn write_last_tab(tab_id: &str) {
    let dir = state_dir();
    let _ = std::fs::create_dir_all(&dir);
    let path = dir.join("last-tab");
    let tmp = dir.join("last-tab.tmp");
    if std::fs::write(&tmp, format!("{tab_id}\n")).is_ok() {
        let _ = std::fs::rename(&tmp, &path);
    }
}

fn pause(msg: &str) {
    println!("{msg}\nPress enter to close.");
    let _ = io::stdout().flush();
    let mut buf = String::new();
    let _ = io::stdin().read_line(&mut buf);
}

// ---------- text helpers ----------

fn fit(text: &str, width: usize) -> String {
    if width == 0 {
        return String::new();
    }
    let chars: Vec<char> = text.chars().collect();
    if chars.len() <= width {
        let mut s = text.to_string();
        s.extend(std::iter::repeat(' ').take(width - chars.len()));
        return s;
    }
    if width <= 1 {
        return chars[..width].iter().collect();
    }
    let mut s: String = chars[..width - 1].iter().collect();
    s.push('.');
    s
}

/// Strip herdr's own "12 foo" numeric prefix (`^\d+\s+`).
fn strip_num_prefix(s: &str) -> String {
    let rest = s.trim_start_matches(|c: char| c.is_ascii_digit());
    if rest.len() < s.len() && rest.starts_with(char::is_whitespace) {
        let stripped = rest.trim_start().to_string();
        if !stripped.is_empty() {
            return stripped;
        }
    }
    s.to_string()
}

fn status_key(status: &str) -> String {
    status.trim().to_lowercase()
}

fn status_badge(status: &str) -> String {
    match status_key(status).as_str() {
        "working" => "working".into(),
        "idle" => "idle   ".into(),
        "done" => "done   ".into(),
        "blocked" => "blocked".into(),
        "unknown" => "?      ".into(),
        _ => {
            let raw = if status.is_empty() { "?" } else { status };
            fit(&raw.chars().take(7).collect::<String>(), 7)
        }
    }
}

/// Foreground color for the status badge; bg is Cyan when selected.
fn status_fg(status: &str, selected: bool) -> Color {
    match status_key(status).as_str() {
        "working" => Color::Yellow,
        "idle" => Color::Green,
        "done" => {
            if selected {
                Color::Blue
            } else {
                Color::Cyan
            }
        }
        "blocked" => Color::Red,
        "unknown" => Color::Magenta,
        _ => {
            if selected {
                Color::Black
            } else {
                Color::White
            }
        }
    }
}

fn is_interesting_status(status: &str) -> bool {
    !matches!(status_key(status).as_str(), "idle" | "unknown")
}

// ---------- tree model ----------

enum Entry {
    Ws { wid: String, label: String, count: usize, expanded: bool },
    Tab { idx: usize, wid: String, is_last: bool },
}

impl Entry {
    fn wid(&self) -> &str {
        match self {
            Entry::Ws { wid, .. } => wid,
            Entry::Tab { wid, .. } => wid,
        }
    }
}

fn filtered_tab_indices(rows: &[Row], filter_on: bool, query: &str) -> Vec<usize> {
    let q = query.trim().to_lowercase();
    (0..rows.len())
        .filter(|&i| !filter_on || is_interesting_status(&rows[i].status))
        .filter(|&i| {
            if q.is_empty() {
                return true;
            }
            let row = &rows[i];
            let hay = format!("{} {} {}", row.tab, row.workspace, row.status).to_lowercase();
            hay.contains(&q)
        })
        .collect()
}

fn workspace_order(rows: &[Row], tab_indices: &[usize]) -> Vec<String> {
    let mut order = Vec::new();
    let mut seen = HashSet::new();
    for &i in tab_indices {
        let wid = &rows[i].workspace_id;
        if seen.insert(wid.clone()) {
            order.push(wid.clone());
        }
    }
    order
}

fn build_entries(rows: &[Row], tab_indices: &[usize], expanded: &HashSet<String>) -> Vec<Entry> {
    let mut by_ws: std::collections::HashMap<&str, Vec<usize>> = std::collections::HashMap::new();
    let mut labels: std::collections::HashMap<&str, &str> = std::collections::HashMap::new();
    for &i in tab_indices {
        by_ws.entry(&rows[i].workspace_id).or_default().push(i);
        labels.insert(&rows[i].workspace_id, &rows[i].workspace);
    }

    let mut entries = Vec::new();
    for wid in workspace_order(rows, tab_indices) {
        let indices = match by_ws.get(wid.as_str()) {
            Some(v) if !v.is_empty() => v,
            _ => continue,
        };
        let is_open = expanded.contains(&wid);
        entries.push(Entry::Ws {
            wid: wid.clone(),
            label: labels.get(wid.as_str()).unwrap_or(&wid.as_str()).to_string(),
            count: indices.len(),
            expanded: is_open,
        });
        if is_open {
            for (n, &i) in indices.iter().enumerate() {
                entries.push(Entry::Tab {
                    idx: i,
                    wid: wid.clone(),
                    is_last: n == indices.len() - 1,
                });
            }
        }
    }
    entries
}

// ---------- drawing ----------

#[derive(Clone, Copy, Default)]
struct St {
    fg: Option<Color>,
    bg: Option<Color>,
    bold: bool,
    dim: bool,
}

impl St {
    fn dim() -> Self {
        St { dim: true, ..Default::default() }
    }
    fn bold() -> Self {
        St { bold: true, ..Default::default() }
    }
}

fn put(out: &mut impl Write, scr_w: u16, y: u16, x: u16, text: &str, st: St) {
    if x >= scr_w {
        return;
    }
    let avail = (scr_w - x).saturating_sub(1) as usize;
    let chunk: String = text.chars().take(avail).collect();
    if chunk.is_empty() {
        return;
    }
    let _ = queue!(out, MoveTo(x, y));
    if let Some(fg) = st.fg {
        let _ = queue!(out, SetForegroundColor(fg));
    }
    if let Some(bg) = st.bg {
        let _ = queue!(out, SetBackgroundColor(bg));
    }
    if st.bold {
        let _ = queue!(out, SetAttribute(Attribute::Bold));
    }
    if st.dim {
        let _ = queue!(out, SetAttribute(Attribute::Dim));
    }
    let _ = queue!(out, Print(chunk), SetAttribute(Attribute::Reset), ResetColor);
}

// ---------- picker UI ----------

fn scroll_top(cursor: usize, view_h: usize) -> usize {
    let mut top = 0usize;
    if cursor >= top + view_h {
        top = cursor - view_h + 1;
    }
    if cursor < top {
        top = cursor;
    }
    top
}

fn pick_index(rows: &[Row], start: usize, last_id: Option<&str>) -> io::Result<Option<usize>> {
    let mut out = io::stdout();
    terminal::enable_raw_mode()?;
    execute!(out, EnterAlternateScreen, Hide, EnableMouseCapture)?;
    let res = ui_loop(&mut out, rows, start, last_id);
    let _ = execute!(out, DisableMouseCapture, Show, LeaveAlternateScreen);
    let _ = terminal::disable_raw_mode();
    res
}

fn ui_loop(
    out: &mut impl Write,
    rows: &[Row],
    start: usize,
    last_id: Option<&str>,
) -> io::Result<Option<usize>> {
    let (branch, branch_last) = ("├─ ", "└─ ");
    let (open_icon, shut_icon) = ("▾ ", "▸ ");
    let (cur_mark, last_mark) = ("●", "○");

    let mut filter_on = false;
    let mut query = String::new();
    let mut query_mode = false;
    let start_idx = start.min(rows.len().saturating_sub(1));
    // Default: expand every workspace; h/l still folds.
    let mut expanded: HashSet<String> = rows.iter().map(|r| r.workspace_id.clone()).collect();
    let mut cursor = 0usize;

    // Place cursor on the starting tab after first build.
    let first = build_entries(rows, &filtered_tab_indices(rows, filter_on, &query), &expanded);
    for (i, ent) in first.iter().enumerate() {
        if let Entry::Tab { idx, .. } = ent {
            if *idx == start_idx {
                cursor = i;
                break;
            }
        }
    }

    loop {
        let tab_indices = filtered_tab_indices(rows, filter_on, &query);
        let entries = build_entries(rows, &tab_indices, &expanded);
        cursor = cursor.min(entries.len().saturating_sub(1));

        let (width, height) = terminal::size()?;
        queue!(out, Clear(ClearType::All))?;

        if height < 4 || width < 16 {
            put(out, width, 0, 0, "window too small", St::bold());
            out.flush()?;
            if let Event::Key(k) = crossterm::event::read()? {
                if k.kind == KeyEventKind::Press
                    && matches!(k.code, KeyCode::Esc | KeyCode::Char('q'))
                {
                    return Ok(None);
                }
            }
            continue;
        }

        let inner = (width - 1) as usize;
        let help_l = if query_mode {
            format!("/{query}█  arrows move  esc done  ^u clear")
        } else {
            "j/k · 1-9 · n last · / filter · click · h/l fold · enter · f · esc".to_string()
        };
        put(out, width, 0, 1, &fit(&help_l, inner.saturating_sub(1)), St::dim());
        let mut flags = String::new();
        if filter_on {
            flags.push('F');
        }
        if !query.is_empty() {
            flags.push('/');
        }
        if !flags.is_empty() {
            let x = inner.saturating_sub(flags.len() + 1) as u16;
            put(out, width, 0, x, &flags, St::bold());
        }

        let w_st = 7usize;
        let w_tab = 12usize.max(inner.saturating_sub(19));
        let sep = format!(" {}", "─".repeat(inner.saturating_sub(2)));
        put(out, width, 1, 0, &fit(&sep, inner), St::dim());

        let list_top = 2usize;
        let footer_row = (height - 1) as usize;
        let sep_bottom = (height - 2) as usize;
        let view_h = 1usize.max(sep_bottom - list_top);

        // 1-9 jump numbers over visible tab entries.
        let mut tab_ord: std::collections::HashMap<usize, usize> = std::collections::HashMap::new();
        let mut n_vis = 0usize;
        for (e_i, ent) in entries.iter().enumerate() {
            if matches!(ent, Entry::Tab { .. }) {
                n_vis += 1;
                if n_vis <= 9 {
                    tab_ord.insert(e_i, n_vis);
                }
            }
        }

        if entries.is_empty() {
            let mut empty_msg = "no matches".to_string();
            if !query.is_empty() {
                empty_msg += " — edit / or ^u clear";
            } else if filter_on {
                empty_msg += " — press f";
            }
            put(out, width, list_top as u16, 1, &fit(&empty_msg, inner.saturating_sub(1)), St::dim());
        } else {
            let top = scroll_top(cursor, view_h);
            for row_i in 0..view_h {
                let e_i = top + row_i;
                if e_i >= entries.len() {
                    break;
                }
                let ent = &entries[e_i];
                let selected = e_i == cursor;
                let y = (list_top + row_i) as u16;

                let base = if selected {
                    St { fg: Some(Color::Black), bg: Some(Color::Cyan), bold: true, dim: false }
                } else {
                    St::bold()
                };
                let tree = if selected {
                    St { fg: Some(Color::Black), bg: Some(Color::Cyan), bold: false, dim: true }
                } else {
                    St { fg: Some(Color::White), bg: None, bold: false, dim: true }
                };
                if selected {
                    put(out, width, y, 0, &" ".repeat(inner), base);
                }

                match ent {
                    Entry::Ws { label, count, expanded: is_open, .. } => {
                        let icon = if *is_open { open_icon } else { shut_icon };
                        let mut text = label.clone();
                        if !is_open {
                            text += &format!("  ({count})");
                        }
                        put(out, width, y, 1, icon, tree);
                        let icon_len = icon.chars().count();
                        put(
                            out,
                            width,
                            y,
                            (1 + icon_len) as u16,
                            &fit(&text, inner.saturating_sub(1 + icon_len)),
                            base,
                        );
                    }
                    Entry::Tab { idx, is_last: leaf_last, .. } => {
                        let row = &rows[*idx];
                        let is_current = row.focused;
                        let is_last =
                            last_id.is_some_and(|l| l == row.tab_id) && !is_current;
                        let twig = if *leaf_last { branch_last } else { branch };
                        let name = strip_num_prefix(&row.tab);
                        let badge = status_badge(&row.status);
                        // cols: 1 branch(3) | 4 num(2) | 6 cur(2) | 8 last(2) | 10 name
                        let name_w = 8usize.max(w_tab.min(inner.saturating_sub(10 + 2 + w_st)));
                        let badge_at = 10 + name_w + 2;
                        put(out, width, y, 1, twig, tree);
                        let num_cell = match tab_ord.get(&e_i) {
                            Some(n) => format!("{n} "),
                            None => "  ".into(),
                        };
                        put(out, width, y, 4, &num_cell, if selected { base } else { tree });
                        let cur_cell = if is_current { format!("{cur_mark} ") } else { "  ".into() };
                        let cur_attr = if is_current {
                            if selected {
                                base
                            } else {
                                St { fg: Some(Color::Cyan), bg: None, bold: true, dim: false }
                            }
                        } else {
                            tree
                        };
                        let last_cell = if is_last { format!("{last_mark} ") } else { "  ".into() };
                        let last_attr = if is_last {
                            if selected {
                                base
                            } else {
                                St { fg: Some(Color::Yellow), bg: None, bold: true, dim: false }
                            }
                        } else {
                            tree
                        };
                        put(out, width, y, 6, &cur_cell, cur_attr);
                        put(out, width, y, 8, &last_cell, last_attr);
                        put(out, width, y, 10, &fit(&name, name_w), base);
                        if badge_at < inner {
                            let badge_st = St {
                                fg: Some(status_fg(&row.status, selected)),
                                bg: selected.then_some(Color::Cyan),
                                bold: true,
                                dim: false,
                            };
                            put(
                                out,
                                width,
                                y,
                                badge_at as u16,
                                &fit(&badge, w_st.min(inner.saturating_sub(badge_at))),
                                badge_st,
                            );
                        }
                    }
                }
            }
        }

        put(out, width, sep_bottom as u16, 0, &sep, St::dim());

        let footer = if entries.is_empty() {
            let mut f = "0/0".to_string();
            if !query.is_empty() {
                f += &format!(" /{query}");
            }
            f
        } else {
            let mut f = format!("{}/{}", cursor + 1, entries.len());
            if filter_on {
                f += " F";
            }
            if !query.is_empty() {
                f += &format!(" /{query}");
            }
            if let Entry::Ws { expanded: is_open, .. } = &entries[cursor] {
                f += match (query_mode, is_open) {
                    (true, true) => " ← fold",
                    (true, false) => " → open",
                    (false, true) => " h fold",
                    (false, false) => " l open",
                };
            }
            f
        };
        put(out, width, footer_row as u16, 0, &fit(&footer, inner), St::dim());

        out.flush()?;

        // ---------- input ----------
        let ev = crossterm::event::read()?;

        let move_down = |cursor: &mut usize| {
            if !entries.is_empty() {
                *cursor = (*cursor + 1) % entries.len();
            }
        };
        let move_up = |cursor: &mut usize| {
            if !entries.is_empty() {
                *cursor = (*cursor + entries.len() - 1) % entries.len();
            }
        };

        // fold/activate need &mut expanded; implement inline below.
        macro_rules! fold_right {
            () => {
                if let Some(ent) = entries.get(cursor) {
                    expanded.insert(ent.wid().to_string());
                }
            };
        }
        macro_rules! fold_left {
            () => {
                if let Some(ent) = entries.get(cursor) {
                    let wid = ent.wid().to_string();
                    expanded.remove(&wid);
                    // Snap cursor to the folded workspace node.
                    let entries2 = build_entries(
                        rows,
                        &filtered_tab_indices(rows, filter_on, &query),
                        &expanded,
                    );
                    let mut found = None;
                    for (i, e) in entries2.iter().enumerate() {
                        if matches!(e, Entry::Ws { .. }) && e.wid() == wid {
                            found = Some(i);
                            break;
                        }
                    }
                    cursor = found.unwrap_or(cursor.min(entries2.len().saturating_sub(1)));
                }
            };
        }
        macro_rules! activate {
            () => {{
                let mut picked: Option<usize> = None;
                if let Some(ent) = entries.get(cursor) {
                    match ent {
                        Entry::Tab { idx, .. } => picked = Some(*idx),
                        Entry::Ws { wid, expanded: is_open, .. } => {
                            if *is_open {
                                expanded.remove(wid);
                            } else {
                                expanded.insert(wid.clone());
                            }
                        }
                    }
                }
                picked
            }};
        }

        match ev {
            Event::Mouse(m) => {
                if matches!(m.kind, MouseEventKind::Down(MouseButton::Left)) && !entries.is_empty() {
                    let my = m.row as usize;
                    let top = scroll_top(cursor, view_h);
                    if my >= list_top && my < list_top + view_h {
                        let e_i = top + (my - list_top);
                        if e_i < entries.len() {
                            cursor = e_i;
                            if let Some(picked) = activate!() {
                                return Ok(Some(picked));
                            }
                        }
                    }
                }
            }
            Event::Key(k) if k.kind == KeyEventKind::Press || k.kind == KeyEventKind::Repeat => {
                if query_mode {
                    match k.code {
                        KeyCode::Esc => query_mode = false,
                        KeyCode::Char('u') if k.modifiers.contains(KeyModifiers::CONTROL) => {
                            query.clear()
                        }
                        KeyCode::Backspace => {
                            query.pop();
                        }
                        KeyCode::Up => move_up(&mut cursor),
                        KeyCode::Down => move_down(&mut cursor),
                        KeyCode::Left => fold_left!(),
                        KeyCode::Right => fold_right!(),
                        KeyCode::Enter => {
                            if let Some(picked) = activate!() {
                                return Ok(Some(picked));
                            }
                        }
                        KeyCode::Char(c)
                            if !k.modifiers.contains(KeyModifiers::CONTROL)
                                && (' '..='~').contains(&c) =>
                        {
                            query.push(c)
                        }
                        _ => {}
                    }
                    continue;
                }
                match k.code {
                    KeyCode::Char('j') | KeyCode::Down => move_down(&mut cursor),
                    KeyCode::Char('k') | KeyCode::Up => move_up(&mut cursor),
                    KeyCode::Char('l') | KeyCode::Right => fold_right!(),
                    KeyCode::Char('h') | KeyCode::Left => fold_left!(),
                    KeyCode::Char('f') | KeyCode::Char('F') => filter_on = !filter_on,
                    KeyCode::Char('/') => query_mode = true,
                    KeyCode::Char('n') => {
                        if let Some(last) = last_id {
                            if let Some(i) = rows.iter().position(|r| r.tab_id == last) {
                                return Ok(Some(i));
                            }
                        }
                    }
                    KeyCode::Char(c @ '1'..='9') => {
                        let want = c as usize - '0' as usize;
                        let mut seen = 0usize;
                        for ent in &entries {
                            if let Entry::Tab { idx, .. } = ent {
                                seen += 1;
                                if seen == want {
                                    return Ok(Some(*idx));
                                }
                            }
                        }
                    }
                    KeyCode::Enter => {
                        if let Some(picked) = activate!() {
                            return Ok(Some(picked));
                        }
                    }
                    KeyCode::Esc => {
                        if !query.is_empty() {
                            query.clear();
                        } else {
                            return Ok(None);
                        }
                    }
                    KeyCode::Char('q') => return Ok(None),
                    _ => {}
                }
            }
            _ => {} // resize etc: just redraw
        }
    }
}

// ---------- open mode ----------

fn popup_size(bin: &str) -> (usize, usize) {
    let tabs = herdr_json(bin, &["tab", "list"])
        .ok()
        .and_then(|r| r.get("tabs").and_then(|t| t.as_array()).cloned())
        .unwrap_or_default();
    let workspaces = load_workspaces(bin);

    let mut max_line = "  tab  workspace  RUN ".chars().count();
    for tab in &tabs {
        let wid = json_str(tab, "workspace_id").unwrap_or_else(|| "?".into());
        let wlabel = workspaces.get(&wid).cloned().unwrap_or_else(|| wid.clone());
        let tlabel = json_str(tab, "label")
            .filter(|s| !s.is_empty())
            .or_else(|| json_str(tab, "tab_id"))
            .unwrap_or_default();
        let status = json_str(tab, "agent_status").unwrap_or_default();
        // marker + tab + gaps + workspace + badge
        let line_len =
            2 + tlabel.chars().count() + 2 + wlabel.chars().count() + 2 + 4usize.max(status.len());
        max_line = max_line.max(line_len);
    }

    let (cols, lines) = terminal::size().unwrap_or((100, 30));
    let (cols, lines) = (cols as usize, lines as usize);
    let n = 1usize.max(tabs.len());
    // chrome ≈ help + seps + footer + border
    let height = 10usize.max((n + 8).min(10usize.max(lines * 85 / 100)));
    // Tree needs room for branch + long tab names + status column.
    let width = 48usize.max((max_line + 14).max(48).min(48usize.max(cols * 92 / 100)));
    (width, height)
}

fn open_mode(bin: &str) -> i32 {
    let (width, height) = popup_size(bin);
    let err = Command::new(bin)
        .args([
            "plugin",
            "pane",
            "open",
            "--plugin",
            "local.tab-goto-rs",
            "--entrypoint",
            "picker",
            "--placement",
            "popup",
            "--width",
            &width.to_string(),
            "--height",
            &height.to_string(),
            "--focus",
        ])
        .exec();
    eprintln!("failed to exec herdr: {err}");
    1
}

// ---------- picker main ----------

fn picker_mode(bin: &str) -> i32 {
    if !io::stdin().is_terminal() || !io::stdout().is_terminal() {
        pause("tab-goto needs a TTY (run from herdr popup).");
        return 1;
    }

    let rows = match load_tabs(bin) {
        Ok(r) => r,
        Err(e) => {
            pause(&format!("Failed to list tabs: {e}"));
            return 1;
        }
    };
    if rows.is_empty() {
        pause("No tabs in this session.");
        return 0;
    }

    let start = initial_index(&rows);
    let here_id = rows[start].tab_id.clone();
    let last_id = read_last_tab();

    let chosen = match pick_index(&rows, start, last_id.as_deref()) {
        Ok(c) => c,
        Err(e) => {
            pause(&format!("TUI failed: {e}"));
            return 1;
        }
    };
    let Some(chosen) = chosen else { return 0 };

    let tab_id = &rows[chosen].tab_id;
    if *tab_id != here_id {
        write_last_tab(&here_id);
    }
    let ok = Command::new(bin)
        .args(["tab", "focus", tab_id])
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false);
    if !ok {
        pause(&format!("herdr tab focus failed for {tab_id}"));
        return 1;
    }
    0
}

fn main() {
    let mode = std::env::args().nth(1).unwrap_or_else(|| "picker".into());
    let bin = match herdr_bin() {
        Ok(b) => b,
        Err(e) => {
            pause(&e);
            std::process::exit(1);
        }
    };
    let code = match mode.as_str() {
        "open" => open_mode(&bin),
        "picker" => picker_mode(&bin),
        other => {
            eprintln!("unknown mode: {other} (use open|picker)");
            2
        }
    };
    std::process::exit(code);
}
