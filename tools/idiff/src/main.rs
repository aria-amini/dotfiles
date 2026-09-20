use image::{DynamicImage, Rgba, RgbaImage};
use std::env;
use std::io::{self, BufWriter, Write};
use std::path::PathBuf;
use std::process::{self, Command};

#[cfg(feature = "svg")]
mod svg;

mod cli;
mod repo;

fn main() {
    cli::Idiff::parse().dispatch();
}

/// One reviewable file: two materialized sides plus a display label.
pub(crate) struct Pair {
    pub(crate) label: String,
    pub(crate) status: Option<repo::Status>,
    pub(crate) before: Option<PathBuf>,
    pub(crate) after: Option<PathBuf>,
}

#[derive(Clone, Copy, PartialEq)]
enum CompareMode {
    TwoUp,
    Swipe,
    OnionSkin,
    Difference,
    Left,
    Right,
}

impl CompareMode {
    /// Cycle to next comparison mode. Single-image modes are skipped;
    /// they're only reachable via the `s` key.
    fn next(self) -> Self {
        match self {
            Self::TwoUp => Self::Swipe,
            Self::Swipe => Self::OnionSkin,
            Self::OnionSkin => Self::Difference,
            Self::Difference => Self::TwoUp,
            Self::Left | Self::Right => Self::TwoUp,
        }
    }
    fn label(self) -> &'static str {
        match self {
            Self::TwoUp => "2-up",
            Self::Swipe => "swipe",
            Self::OnionSkin => "onion skin",
            Self::Difference => "difference",
            Self::Left => "left only",
            Self::Right => "right only",
        }
    }
    fn uses_slider(self) -> bool {
        matches!(self, Self::Swipe | Self::OnionSkin)
    }
    fn is_single(self) -> bool {
        matches!(self, Self::Left | Self::Right)
    }
}

/// Lay out both images on a common canvas (max of both dimensions),
/// so that identical pixel coordinates line up for swipe/onion comparison.
fn normalize_pair(a: &DynamicImage, b: &DynamicImage) -> (RgbaImage, RgbaImage) {
    let w = a.width().max(b.width());
    let h = a.height().max(b.height());
    let mut out_a = RgbaImage::from_pixel(w, h, Rgba([0, 0, 0, 0]));
    let mut out_b = RgbaImage::from_pixel(w, h, Rgba([0, 0, 0, 0]));
    image::imageops::overlay(&mut out_a, &a.to_rgba8(), 0, 0);
    image::imageops::overlay(&mut out_b, &b.to_rgba8(), 0, 0);
    (out_a, out_b)
}

/// Scale two same-sized images by the same factor to fit a bounding box.
fn scale_pair(a: &RgbaImage, b: &RgbaImage, max_w: u32, max_h: u32) -> (RgbaImage, RgbaImage) {
    let (w, h) = (a.width(), a.height());
    if w <= max_w && h <= max_h {
        return (a.clone(), b.clone());
    }
    let scale = (max_w as f64 / w as f64).min(max_h as f64 / h as f64);
    let nw = ((w as f64 * scale) as u32).max(1);
    let nh = ((h as f64 * scale) as u32).max(1);
    (
        image::imageops::resize(a, nw, nh, image::imageops::FilterType::Triangle),
        image::imageops::resize(b, nw, nh, image::imageops::FilterType::Triangle),
    )
}

fn compose_two_up(a: &RgbaImage, b: &RgbaImage, max_w: u32, max_h: u32) -> RgbaImage {
    let sep = 4u32;
    let half = max_w.saturating_sub(sep) / 2;
    let sa = scale_rgba(a, half, max_h);
    let sb = scale_rgba(b, half, max_h);
    let th = sa.height().max(sb.height());
    let canvas_w = sa.width() + sep + sb.width();
    let mut canvas = RgbaImage::new(canvas_w, th);
    let gray = Rgba([128, 128, 128, 255]);
    for y in 0..th {
        for x in sa.width()..(sa.width() + sep) {
            canvas.put_pixel(x, y, gray);
        }
    }
    let sa_w = sa.width();
    image::imageops::overlay(&mut canvas, &sa, 0, 0);
    image::imageops::overlay(&mut canvas, &sb, (sa_w + sep) as i64, 0);
    canvas
}

fn compose_swipe(a: &RgbaImage, b: &RgbaImage, t: f32) -> RgbaImage {
    let (w, h) = a.dimensions();
    let split = ((w as f32) * t.clamp(0.0, 1.0)) as u32;
    let row_bytes = (w * 4) as usize;
    let split_bytes = (split * 4) as usize;
    let ra = a.as_raw();
    let rb = b.as_raw();
    let mut out = vec![0u8; ra.len()];
    // Row-wise slice copy: left half from `a`, right half from `b`.
    for y in 0..(h as usize) {
        let base = y * row_bytes;
        let mid = base + split_bytes;
        let end = base + row_bytes;
        out[base..mid].copy_from_slice(&ra[base..mid]);
        out[mid..end].copy_from_slice(&rb[mid..end]);
        // Draw 1px yellow divider where the split lands.
        if split < w {
            let off = base + split_bytes;
            out[off] = 255;
            out[off + 1] = 220;
            out[off + 2] = 0;
            out[off + 3] = 255;
        }
    }
    RgbaImage::from_raw(w, h, out).expect("swipe buffer size matches")
}

fn compose_onion(a: &RgbaImage, b: &RgbaImage, t: f32) -> RgbaImage {
    let t = (t.clamp(0.0, 1.0) * 255.0 + 0.5) as u32;
    let inv = 255 - t;
    let (w, h) = a.dimensions();
    let ra = a.as_raw();
    let rb = b.as_raw();
    let mut out = vec![0u8; ra.len()];
    // Integer blend: (a*(255-t) + b*t + 127) / 255, applied to all channels.
    for i in 0..ra.len() {
        out[i] = ((ra[i] as u32 * inv + rb[i] as u32 * t + 127) / 255) as u8;
    }
    RgbaImage::from_raw(w, h, out).expect("onion buffer size matches")
}

fn draw_status_bar(
    w: &mut impl Write,
    cols: u16,
    rows: u16,
    slider: f32,
    mode: CompareMode,
    multi: bool,
) -> io::Result<()> {
    let slider_row = rows.saturating_sub(2).max(1);
    let help_row = rows.saturating_sub(1).max(1);

    // Slider line — only drawn for modes that respond to it. The row is
    // always cleared so the previous mode's slider doesn't linger.
    write!(w, "\x1b[{};1H\x1b[2K", slider_row + 1)?;
    if mode.uses_slider() {
        let pct = (slider * 100.0).round() as u32;
        let label = format!(" {:3}%", pct);
        let bar_width = (cols as usize).saturating_sub(label.len() + 2).max(10);
        let pos = ((bar_width as f32) * slider) as usize;
        write!(w, "[")?;
        for i in 0..bar_width {
            if i == pos.min(bar_width - 1) {
                write!(w, "\x1b[33m█\x1b[0m")?;
            } else if i < pos {
                write!(w, "=")?;
            } else {
                write!(w, "-")?;
            }
        }
        write!(w, "]{}", label)?;
    }

    // Help line
    write!(w, "\x1b[{};1H\x1b[2K", help_row + 1)?;
    let files = if multi {
        "   [ ] file   f tv pick   "
    } else {
        ""
    };
    write!(
        w,
        "mode: \x1b[1m{}\x1b[0m    \x1b[2m←/→ slider   m mode   s side{}  q quit\x1b[0m",
        mode.label(),
        files
    )?;
    Ok(())
}

struct InteractiveCache {
    cols: u16,
    rows: u16,
    usable_rows: u16,
    term_px_w: u32,
    term_px_h: u32,
    /// Pixels per terminal cell row (graphics protocols) or 2 (ANSI half-block).
    cell_h: u32,
    /// Pixels per terminal cell column (graphics protocols) or 1 (ANSI half-block).
    cell_w: u32,
    scaled_a: RgbaImage,
    scaled_b: RgbaImage,
    /// Pre-rendered heatmap of pixel differences, sized to match `scaled_a`/
    /// `scaled_b` so the difference mode can blit it directly.
    scaled_diff: RgbaImage,
    /// Built once per resize for the Sixel protocol. Approximates onion-skin
    /// blend colors via nearest-color lookup.
    sixel_palette: Option<SixelPalette>,
}

/// Reserve 3 bottom rows for spacer + slider + help.
const INTERACTIVE_BOTTOM_ROWS: u16 = 3;
/// Conservative Sixel raster cap. Matches xterm's default `maxGraphicSize`,
/// so a 2-up canvas at this size displays in essentially every Sixel-capable
/// terminal without tripping per-image or per-sequence buffer limits.
const MAX_SIXEL_W: u32 = 1000;
const MAX_SIXEL_H: u32 = 1000;

fn compute_interactive_cache(
    img1: &DynamicImage,
    img2: &DynamicImage,
    protocol: &Protocol,
    sixel_colors: usize,
    top_rows: u16,
) -> InteractiveCache {
    let (cols, rows) = crossterm::terminal::size().unwrap_or((80, 24));
    let usable_rows = rows
        .saturating_sub(top_rows + INTERACTIVE_BOTTOM_ROWS)
        .max(1);

    let (term_px_w, term_px_h, cell_h, cell_w) = match protocol {
        Protocol::Ansi => (cols as u32, usable_rows as u32 * 2, 2u32, 1u32),
        _ => {
            let (fw, fh) = query_pixel_size().unwrap_or((cols as u32 * 8, rows as u32 * 16));
            let cell_h = (fh / rows.max(1) as u32).max(1);
            let cell_w = (fw / cols.max(1) as u32).max(1);
            let usable_px_h = usable_rows as u32 * cell_h;
            let (w_px, h_px) = if matches!(protocol, Protocol::Sixel) {
                (fw.min(MAX_SIXEL_W), usable_px_h.min(MAX_SIXEL_H))
            } else {
                (fw, usable_px_h)
            };
            (w_px, h_px, cell_h, cell_w)
        }
    };

    let (na, nb) = normalize_pair(img1, img2);
    let (scaled_a, scaled_b) = scale_pair(&na, &nb, term_px_w, term_px_h);

    // Build the diff heatmap on the original images (so out-of-overlap regions
    // stay magenta), then scale by the same factor so it lines up with
    // `scaled_a`/`scaled_b` pixel-for-pixel.
    let diff_full = build_diff_heatmap(img1, img2);
    let scaled_diff = scale_rgba(&diff_full, term_px_w, term_px_h);

    let sixel_palette = if matches!(protocol, Protocol::Sixel) {
        Some(SixelPalette::from_images(
            &[&scaled_a, &scaled_b, &scaled_diff],
            sixel_colors,
        ))
    } else {
        None
    };

    InteractiveCache {
        cols,
        rows,
        usable_rows,
        term_px_w,
        term_px_h,
        cell_h,
        cell_w,
        scaled_a,
        scaled_b,
        scaled_diff,
        sixel_palette,
    }
}

/// Image height in terminal cell rows, given the composed image and cell pixel height.
fn image_cell_rows(img_h: u32, protocol: &Protocol, cell_h: u32) -> u32 {
    match protocol {
        Protocol::Ansi => img_h.div_ceil(2),
        _ => img_h.div_ceil(cell_h).max(1),
    }
}

/// Image width in terminal cell columns, given the composed image and cell pixel width.
fn image_cell_cols(img_w: u32, protocol: &Protocol, cell_w: u32) -> u32 {
    match protocol {
        Protocol::Ansi => img_w.max(1),
        _ => img_w.div_ceil(cell_w).max(1),
    }
}

/// Solid white canvas used for the missing side of an added/deleted image.
fn placeholder_canvas(w: u32, h: u32) -> RgbaImage {
    RgbaImage::from_pixel(w.max(1), h.max(1), Rgba([255, 255, 255, 255]))
}

/// Plain list of changed files for orientation and direct jumps. A screen
/// clear does not remove kitty placements, so delete them explicitly.
fn render_file_list(
    session: &Session,
    sel: usize,
    protocol: &Protocol,
    w: &mut impl Write,
) -> io::Result<()> {
    let (cols, rows) = crossterm::terminal::size().unwrap_or((80, 24));
    w.write_all(b"\x1b[2J\x1b[H")?;
    if matches!(protocol, Protocol::Kitty) {
        w.write_all(&kitty_clear_placements())?;
    }
    writeln!(
        w,
        "\x1b[1midiff\x1b[0m  {}/{}  \x1b[2mEnter open · Esc close\x1b[0m",
        sel + 1,
        session.pairs.len()
    )?;
    let list_rows = (rows as usize).saturating_sub(2).max(1);
    let visible = list_rows.min(session.pairs.len());
    let offset = sel
        .saturating_sub(visible.saturating_sub(1))
        .min(session.pairs.len().saturating_sub(visible));
    for (row, i) in (offset..offset + visible).enumerate() {
        let pair = &session.pairs[i];
        let marker = if i == sel { "❯" } else { " " };
        let mut line = format!("{marker} {}", pair.label);
        if let Some(s) = pair.status {
            line.push_str(&format!("  {}", s.label()));
        }
        let line: String = line.chars().take(cols as usize).collect();
        write!(w, "\x1b[{};1H\x1b[2K", row + 2)?;
        if i == sel {
            write!(w, "\x1b[7m{line}\x1b[0m")?;
        } else {
            write!(w, "{line}")?;
        }
    }
    w.flush()
}

fn draw_header(w: &mut impl Write, cols: u16, text: &str) -> io::Result<()> {
    write!(w, "\x1b[1;1H\x1b[2K")?;
    let line: String = text.chars().take(cols as usize).collect();
    write!(w, "{line}")
}

#[allow(clippy::too_many_arguments)]
fn render_interactive_frame(
    img1: &DynamicImage,
    img2: &DynamicImage,
    cached: &mut Option<InteractiveCache>,
    mode: CompareMode,
    slider: f32,
    protocol: &Protocol,
    sixel_colors: usize,
    meta: &str,
    header: Option<&str>,
    top_rows: u16,
    full_redraw: bool,
    w: &mut impl Write,
) -> io::Result<()> {
    if cached.is_none() {
        *cached = Some(compute_interactive_cache(
            img1,
            img2,
            protocol,
            sixel_colors,
            top_rows,
        ));
    }
    let c = cached.as_ref().unwrap();

    // Build the new frame fully into an in-memory buffer before touching the
    // terminal, so the existing frame stays visible while we compose and
    // encode. Once the buffer is ready, we clear and blit in one shot.
    let mut frame: Vec<u8> = Vec::with_capacity(64 * 1024);

    let composed = match mode {
        CompareMode::TwoUp => compose_two_up(&c.scaled_a, &c.scaled_b, c.term_px_w, c.term_px_h),
        CompareMode::Swipe => compose_swipe(&c.scaled_a, &c.scaled_b, slider),
        CompareMode::OnionSkin => compose_onion(&c.scaled_a, &c.scaled_b, slider),
        CompareMode::Difference => c.scaled_diff.clone(),
        CompareMode::Left => c.scaled_a.clone(),
        CompareMode::Right => c.scaled_b.clone(),
    };

    // Center the image within the usable rows region (vertical) and full width.
    let img_rows = image_cell_rows(composed.height(), protocol, c.cell_h);
    let top_pad = (c.usable_rows as u32).saturating_sub(img_rows) / 2;
    let img_cols = image_cell_cols(composed.width(), protocol, c.cell_w);
    let left_pad = (c.cols as u32).saturating_sub(img_cols) / 2;
    let img_top_row = top_pad + 1 + top_rows as u32;
    write!(frame, "\x1b[{};{}H", img_top_row, left_pad + 1)?;

    match protocol {
        Protocol::Kitty => write_kitty(&composed, &mut frame)?,
        Protocol::Iterm2 => write_iterm2(&composed, &mut frame)?,
        Protocol::Sixel => {
            // The cache is guaranteed to hold a palette for the Sixel protocol.
            let palette = c.sixel_palette.as_ref().expect("sixel palette cached");
            write_sixel(&composed, palette, &mut frame)?
        }
        Protocol::Ansi => write_text(&composed, left_pad, &mut frame)?,
    }

    if let Some(header) = header {
        draw_header(&mut frame, c.cols, header)?;
    }
    draw_meta_line(&mut frame, c.cols, top_rows, meta)?;
    draw_status_bar(&mut frame, c.cols, c.rows, slider, mode, header.is_some())?;

    // Clear the screen (or skip it for in-place updates) and emit the
    // pre-rendered frame in a single flush. For Sixel/ANSI we can overwrite
    // the previous image exactly as long as the layout is unchanged — no
    // resize, no mode switch — which avoids the flicker of a full clear.
    let skip_clear = !full_redraw && matches!(protocol, Protocol::Sixel | Protocol::Ansi);
    if !skip_clear {
        w.write_all(b"\x1b[2J\x1b[H")?;
        // Kitty: also delete any prior image placements.
        if matches!(protocol, Protocol::Kitty) {
            w.write_all(&kitty_clear_placements())?;
        }
    }

    w.write_all(&frame)?;
    w.flush()
}

/// Loaded state for the pair currently on screen.
struct Session<'a> {
    pairs: &'a [Pair],
    idx: usize,
    loaded: Option<usize>,
    img1: DynamicImage,
    img2: DynamicImage,
    meta: String,
}

impl Session<'_> {
    /// Load both sides of pair `idx`, substituting a white placeholder for a
    /// missing (added/deleted) or unreadable side. The placeholder inherits
    /// the other side's dimensions so the diff canvas stays meaningful.
    fn load(&mut self, idx: usize, load_px: (u32, u32)) -> Result<(), String> {
        let pair = &self.pairs[idx];
        let load = |p: &PathBuf| load_image(&p.to_string_lossy(), load_px.0, load_px.1);
        let after = match &pair.after {
            Some(p) => {
                Some(load(p).map_err(|e| format!("Failed to open '{}': {}", p.display(), e))?)
            }
            None => None,
        };
        let before = match &pair.before {
            Some(p) => {
                Some(load(p).map_err(|e| format!("Failed to open '{}': {}", p.display(), e))?)
            }
            None => None,
        };

        let (img1, meta1) = match before {
            Some(img) => {
                let p = pair.before.as_ref().unwrap().to_string_lossy().to_string();
                let m = read_meta(&p, &img);
                (img, m)
            }
            None => {
                let (w, h) = after
                    .as_ref()
                    .map(|i| (i.width(), i.height()))
                    .unwrap_or((1, 1));
                (
                    placeholder_canvas(w, h).into(),
                    ImageMeta {
                        format: "-",
                        width: w,
                        height: h,
                        size: 0,
                    },
                )
            }
        };
        let (img2, meta2) = match after {
            Some(img) => {
                let p = pair.after.as_ref().unwrap().to_string_lossy().to_string();
                let m = read_meta(&p, &img);
                (img, m)
            }
            None => {
                let (w, h) = (img1.width(), img1.height());
                (
                    placeholder_canvas(w, h).into(),
                    ImageMeta {
                        format: "-",
                        width: w,
                        height: h,
                        size: 0,
                    },
                )
            }
        };

        self.meta = format_meta_line(&meta1, &meta2);
        self.img1 = img1;
        self.img2 = img2;
        self.loaded = Some(idx);
        Ok(())
    }

    fn header_text(&self) -> String {
        let pair = &self.pairs[self.idx];
        let pos = if self.pairs.len() > 1 {
            format!("{}/{}  ", self.idx + 1, self.pairs.len())
        } else {
            String::new()
        };
        let status = pair
            .status
            .map(|s| format!("  {}", s.label()))
            .unwrap_or_default();
        format!("{}{}{}", pos, pair.label, status)
    }

    /// Added files have no meaningful baseline and deleted files no
    /// successor, so they open as a single image with mode cycling locked.
    fn forced_mode(&self) -> Option<CompareMode> {
        match self.pairs[self.idx].status {
            Some(repo::Status::Added) => Some(CompareMode::Right),
            Some(repo::Status::Deleted) => Some(CompareMode::Left),
            _ => None,
        }
    }
}

/// Interactive review of the changed-image set. `[` / `]` step between
/// pairs when more than one changed; `f` opens the file list overlay.
pub(crate) fn run_review(
    pairs: &[Pair],
    start: usize,
    renderer: Option<&str>,
    depth: u32,
) -> Result<(), String> {
    let sixel_colors = 1usize << depth;
    let protocol = detect_protocol(renderer);
    let multi = pairs.len() > 1;
    let top_rows: u16 = if multi { 2 } else { 1 };
    let reserve_rows = top_rows + INTERACTIVE_BOTTOM_ROWS;
    // For text mode each terminal cell is 1 char wide and 2 pixels tall
    // (half-blocks); SVG inputs are rasterized at the output size up front.
    let load_px = match protocol {
        Protocol::Ansi => terminal_char_size(reserve_rows),
        _ => terminal_pixel_size(reserve_rows),
    };

    let mut session = Session {
        pairs,
        idx: start,
        loaded: None,
        img1: placeholder_canvas(1, 1).into(),
        img2: placeholder_canvas(1, 1).into(),
        meta: String::new(),
    };

    run_interactive(&mut session, &protocol, sixel_colors, top_rows, load_px)
}

fn run_interactive(
    session: &mut Session,
    protocol: &Protocol,
    sixel_colors: usize,
    top_rows: u16,
    load_px: (u32, u32),
) -> Result<(), String> {
    use crossterm::event::{self, Event, KeyCode, KeyModifiers};
    use std::time::Duration;

    let multi = session.pairs.len() > 1;
    let stdout = io::stdout();
    // Larger-than-default buffer so sixel/kitty frames go out in fewer
    // write() syscalls instead of many 8 KiB chunks.
    let mut out = BufWriter::with_capacity(128 * 1024, stdout.lock());

    crossterm::terminal::enable_raw_mode().map_err(|e| e.to_string())?;
    // Alt screen + hide cursor.
    write!(out, "\x1b[?1049h\x1b[?25l").map_err(|e| e.to_string())?;
    out.flush().map_err(|e| e.to_string())?;

    let mut mode = CompareMode::Swipe;
    // The last non-single comparison mode, so `m` can return to it
    // after jumping into Left/Right via `s`.
    let mut last_compare_mode = CompareMode::Swipe;
    let mut slider: f32 = 0.5;
    let mut cached: Option<InteractiveCache> = None;
    // None until the first successful render, and reset on resize so the
    // next frame forces a full clear.
    let mut last_rendered_mode: Option<CompareMode> = None;
    let mut dirty = true;
    // In-TUI file list overlay: a plain browsable list, no query state.
    let mut picker_open = false;
    let mut picker_sel: usize = 0;
    let mut picker_dirty = true;

    let step = 0.02_f32;

    let mut quit = false;
    let result: Result<(), String> = (|| {
        while !quit {
            if session.loaded != Some(session.idx) {
                match session.load(session.idx, load_px) {
                    Ok(()) => {
                        cached = None;
                        last_rendered_mode = None;
                        dirty = true;
                    }
                    Err(e) => {
                        if session.loaded.is_none() {
                            return Err(e);
                        }
                        // Stay on the current pair; surface the error in the
                        // meta line on the next redraw.
                        session.meta = e;
                        session.idx = session.loaded.unwrap_or(session.idx);
                        cached = None;
                        last_rendered_mode = None;
                        dirty = true;
                    }
                }
            }
            if session.loaded == Some(session.idx)
                && let Some(forced) = session.forced_mode()
                && mode != forced
            {
                mode = forced;
                last_rendered_mode = None;
            }
            let modes_locked = session.forced_mode().is_some();

            if picker_open {
                if picker_dirty {
                    render_file_list(session, picker_sel, protocol, &mut out)
                        .map_err(|e| e.to_string())?;
                    picker_dirty = false;
                }
            } else if dirty {
                let full_redraw = cached.is_none() || last_rendered_mode != Some(mode);
                let header = multi.then(|| session.header_text());
                render_interactive_frame(
                    &session.img1,
                    &session.img2,
                    &mut cached,
                    mode,
                    slider,
                    protocol,
                    sixel_colors,
                    &session.meta,
                    header.as_deref(),
                    top_rows,
                    full_redraw,
                    &mut out,
                )
                .map_err(|e| e.to_string())?;
                last_rendered_mode = Some(mode);
                dirty = false;
            }

            // Block for the next event…
            if !event::poll(Duration::from_millis(250)).map_err(|e| e.to_string())? {
                continue;
            }

            // …then drain any other events already queued (e.g. key-repeat
            // from holding ←/→) so we coalesce them into a single render.
            loop {
                match event::read().map_err(|e| e.to_string())? {
                    Event::Key(k) if picker_open => match k.code {
                        KeyCode::Esc
                        | KeyCode::Char('f')
                        | KeyCode::Char('F')
                        | KeyCode::Char('q') => {
                            picker_open = false;
                            dirty = true;
                        }
                        KeyCode::Enter => {
                            picker_open = false;
                            session.idx = picker_sel;
                            dirty = true;
                        }
                        KeyCode::Up | KeyCode::Char('k') => {
                            picker_sel = picker_sel.saturating_sub(1);
                            picker_dirty = true;
                        }
                        KeyCode::Down | KeyCode::Char('j') => {
                            picker_sel = (picker_sel + 1).min(session.pairs.len() - 1);
                            picker_dirty = true;
                        }
                        _ => {}
                    },
                    Event::Key(k) => match k.code {
                        KeyCode::Char('q') | KeyCode::Esc => {
                            quit = true;
                            break;
                        }
                        KeyCode::Char('c') if k.modifiers.contains(KeyModifiers::CONTROL) => {
                            quit = true;
                            break;
                        }
                        KeyCode::Char('f') | KeyCode::Char('F') if multi => {
                            picker_open = true;
                            picker_sel = session.idx;
                            picker_dirty = true;
                        }
                        KeyCode::Char('m') | KeyCode::Char('M') if !modes_locked => {
                            mode = if mode.is_single() {
                                last_compare_mode
                            } else {
                                let next = mode.next();
                                last_compare_mode = next;
                                next
                            };
                            dirty = true;
                        }
                        KeyCode::Char('s') | KeyCode::Char('S') if !modes_locked => {
                            mode = match mode {
                                CompareMode::Left => CompareMode::Right,
                                CompareMode::Right => CompareMode::Left,
                                other => {
                                    last_compare_mode = other;
                                    CompareMode::Left
                                }
                            };
                            dirty = true;
                        }
                        KeyCode::Char('[') if multi => {
                            session.idx = session.idx.saturating_sub(1);
                        }
                        KeyCode::Char(']') if multi => {
                            session.idx = (session.idx + 1).min(session.pairs.len() - 1);
                        }
                        KeyCode::Left => {
                            let s = if k.modifiers.contains(KeyModifiers::SHIFT) {
                                step * 5.0
                            } else {
                                step
                            };
                            slider = (slider - s).max(0.0);
                            dirty = true;
                        }
                        KeyCode::Right => {
                            let s = if k.modifiers.contains(KeyModifiers::SHIFT) {
                                step * 5.0
                            } else {
                                step
                            };
                            slider = (slider + s).min(1.0);
                            dirty = true;
                        }
                        KeyCode::Home => {
                            slider = 0.0;
                            dirty = true;
                        }
                        KeyCode::End => {
                            slider = 1.0;
                            dirty = true;
                        }
                        _ => {}
                    },
                    Event::Resize(_, _) => {
                        cached = None;
                        last_rendered_mode = None;
                        dirty = true;
                    }
                    _ => {}
                }
                // Stop draining as soon as the queue is empty.
                if !event::poll(Duration::from_millis(0)).map_err(|e| e.to_string())? {
                    break;
                }
            }
        }
        Ok(())
    })();

    // Restore terminal state. Kitty images live in the client's framebuffer
    // across alt-screen switches; delete the placements while the alt screen
    // still owns them.
    if matches!(protocol, Protocol::Kitty) {
        let _ = out.write_all(&kitty_clear_placements());
        let _ = out.flush();
    }
    let _ = write!(out, "\x1b[?25h\x1b[?1049l");
    let _ = out.flush();
    let _ = crossterm::terminal::disable_raw_mode();

    result
}
/// Query terminal size and return available pixel dimensions (width, height),
/// reserving `reserve_rows` text rows at the bottom.
fn terminal_pixel_size(reserve_rows: u16) -> (u32, u32) {
    let (cols, rows) = crossterm::terminal::size().unwrap_or((80, 24));
    let cols = (cols as u32).max(1);
    let rows = (rows as u32).max(1);
    let usable_rows = rows.saturating_sub(reserve_rows as u32);

    // Try CSI 14t query for actual pixel dimensions. Inside tmux, CSI 14t
    // is answered by tmux itself, not the client, so ask tmux for the
    // attached client's pixel size instead.
    if let Some((qw, qh)) = query_pixel_size() {
        let cell_h = qh / rows.max(1);
        let reserved_px = reserve_rows as u32 * cell_h;
        return (qw, qh.saturating_sub(reserved_px).max(1));
    }

    // Last resort: assume 8x16 cells
    (cols * 8, usable_rows * 16)
}

/// Client pixel size, preferring tmux's own knowledge over a CSI 14t query.
fn query_pixel_size() -> Option<(u32, u32)> {
    if env::var("TMUX").is_ok()
        && let Some(px) = tmux_client_pixel_size()
    {
        return Some(px);
    }
    query_pixel_size_csi()
}

fn tmux_client_pixel_size() -> Option<(u32, u32)> {
    let output = Command::new("tmux")
        .args([
            "display-message",
            "-p",
            "#{client_pixel_width} #{client_pixel_height}",
        ])
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let s = String::from_utf8_lossy(&output.stdout);
    let mut parts = s.split_whitespace();
    let w: u32 = parts.next()?.parse().ok()?;
    let h: u32 = parts.next()?.parse().ok()?;
    if w == 0 || h == 0 {
        return None;
    }
    Some((w, h))
}

/// Open a direct read+write handle to the controlling terminal,
/// bypassing stdin/stdout/stderr which may be redirected.
fn open_tty() -> Option<std::fs::File> {
    #[cfg(unix)]
    {
        use std::fs::OpenOptions;
        OpenOptions::new()
            .read(true)
            .write(true)
            .open("/dev/tty")
            .ok()
    }
    #[cfg(windows)]
    {
        use std::fs::OpenOptions;
        // On Windows, CONIN$ and CONOUT$ are separate; open CONOUT$ for write
        // and CONIN$ for read. For simplicity we open CONIN$ read+write — the
        // write end will target the console output.
        OpenOptions::new()
            .read(true)
            .write(true)
            .open("CONIN$")
            .ok()
    }
}

/// Send an escape sequence query to the terminal and read the response.
/// Uses /dev/tty (Unix) or CONIN$/CONOUT$ (Windows) so this works even when
/// stdin/stdout/stderr are redirected (e.g. git external diff commands).
fn query_terminal(query: &[u8], terminator: u8, timeout_ms: u64) -> Option<Vec<u8>> {
    use std::io::Read;
    use std::sync::mpsc;
    use std::time::Duration;

    let mut tty = open_tty()?;

    // Preserve existing raw-mode state: if we're already in raw mode
    // (e.g. inside the interactive TUI loop), don't disable it on the
    // way out — that would unexpectedly re-enable line buffering.
    let was_raw = crossterm::terminal::is_raw_mode_enabled().unwrap_or(false);
    if !was_raw {
        crossterm::terminal::enable_raw_mode().ok()?;
    }

    tty.write_all(query).ok()?;
    tty.flush().ok()?;

    let (tx, rx) = mpsc::channel();
    std::thread::spawn(move || {
        let mut buf = [0u8; 128];
        let mut pos = 0;
        while pos < buf.len() {
            match tty.read(&mut buf[pos..]) {
                Ok(0) => break,
                Ok(n) => {
                    pos += n;
                    if buf[..pos].contains(&terminator) {
                        break;
                    }
                }
                Err(_) => break,
            }
        }
        let _ = tx.send(buf[..pos].to_vec());
    });

    let response = rx.recv_timeout(Duration::from_millis(timeout_ms)).ok();
    if !was_raw {
        let _ = crossterm::terminal::disable_raw_mode();
    }
    response
}

/// Return terminal dimensions suitable for half-block text rendering.
/// Each cell is 1 pixel wide and 2 pixels tall (using ▄).
fn terminal_char_size(reserve_rows: u16) -> (u32, u32) {
    let (cols, rows) = crossterm::terminal::size().unwrap_or((80, 24));
    let usable_rows = (rows as u32).saturating_sub(reserve_rows as u32);
    (cols as u32, usable_rows * 2)
}

/// Query terminal pixel size using xterm CSI 14t escape.
/// Returns Some((width, height)) on success.
fn query_pixel_size_csi() -> Option<(u32, u32)> {
    let data = query_terminal(b"\x1b[14t", b't', 200)?;
    let resp = std::str::from_utf8(&data).ok()?;
    let start = resp.find("[4;")?;
    let rest = &resp[start + 3..];
    let end = rest.find('t')?;
    let nums = &rest[..end];
    let mut parts = nums.split(';');
    let h: u32 = parts.next()?.parse().ok()?;
    let w: u32 = parts.next()?.parse().ok()?;
    Some((w, h))
}

/// Query Sixel support using DA1 (Device Attributes) escape sequence.
/// Sends `ESC [ c` and checks if `4` (Sixel) appears among the reported attributes.
fn query_sixel_support() -> bool {
    let data = match query_terminal(b"\x1b[c", b'c', 200) {
        Some(d) => d,
        None => return false,
    };
    let resp = match std::str::from_utf8(&data) {
        Ok(s) => s,
        Err(_) => return false,
    };
    let start = match resp.find("[?") {
        Some(i) => i + 2,
        None => return false,
    };
    let end = match resp[start..].find('c') {
        Some(i) => start + i,
        None => return false,
    };
    resp[start..end].split(';').any(|p| p.trim() == "4")
}

/// Build a diff heatmap at the native resolution of the two images.
fn build_diff_heatmap(img1: &DynamicImage, img2: &DynamicImage) -> RgbaImage {
    let w1 = img1.width();
    let h1 = img1.height();
    let w2 = img2.width();
    let h2 = img2.height();
    let diff_w = w1.max(w2);
    let diff_h = h1.max(h2);
    let common_w = w1.min(w2);
    let common_h = h1.min(h2);

    let rgba1 = img1.to_rgba8();
    let rgba2 = img2.to_rgba8();
    let raw1 = rgba1.as_raw();
    let raw2 = rgba2.as_raw();

    let mut out = RgbaImage::from_pixel(diff_w, diff_h, Rgba([255, 0, 255, 255]));
    let out_raw = out.as_mut();

    for y in 0..common_h {
        for x in 0..common_w {
            let i1 = ((y * w1 + x) * 4) as usize;
            let i2 = ((y * w2 + x) * 4) as usize;
            let dr = (raw1[i1] as i16 - raw2[i2] as i16).unsigned_abs();
            let dg = (raw1[i1 + 1] as i16 - raw2[i2 + 1] as i16).unsigned_abs();
            let db = (raw1[i1 + 2] as i16 - raw2[i2 + 2] as i16).unsigned_abs();
            let diff = (77 * dr + 151 * dg + 28 * db) as f32 / (255.0 * 256.0);
            let pixel = heatmap_color(diff);
            let oi = ((y * diff_w + x) * 4) as usize;
            out_raw[oi] = pixel[0];
            out_raw[oi + 1] = pixel[1];
            out_raw[oi + 2] = pixel[2];
            out_raw[oi + 3] = pixel[3];
        }
    }

    out
}

/// Scale an RgbaImage to fit within max_w x max_h, preserving aspect ratio.
fn scale_rgba(img: &RgbaImage, max_w: u32, max_h: u32) -> RgbaImage {
    let (w, h) = (img.width(), img.height());
    if w <= max_w && h <= max_h {
        return img.clone();
    }
    let scale = (max_w as f64 / w as f64).min(max_h as f64 / h as f64);
    let new_w = ((w as f64 * scale) as u32).max(1);
    let new_h = ((h as f64 * scale) as u32).max(1);
    image::imageops::resize(img, new_w, new_h, image::imageops::FilterType::Triangle)
}

fn heatmap_color(t: f32) -> Rgba<u8> {
    let t = t.clamp(0.0, 1.0);
    let (r, g, b) = if t < 0.25 {
        let s = t / 0.25;
        (0.0, 0.0, s)
    } else if t < 0.5 {
        let s = (t - 0.25) / 0.25;
        (0.0, s, 1.0 - s)
    } else if t < 0.75 {
        let s = (t - 0.5) / 0.25;
        (s, 1.0, 0.0)
    } else {
        let s = (t - 0.75) / 0.25;
        (1.0, 1.0 - s, 0.0)
    };
    Rgba([(r * 255.0) as u8, (g * 255.0) as u8, (b * 255.0) as u8, 255])
}

enum Protocol {
    Kitty,
    Iterm2,
    Sixel,
    Ansi,
}

fn parse_renderer(name: &str) -> Option<Protocol> {
    match name.to_lowercase().as_str() {
        "kitty" => Some(Protocol::Kitty),
        "iterm2" => Some(Protocol::Iterm2),
        "sixel" => Some(Protocol::Sixel),
        "ansi" => Some(Protocol::Ansi),
        _ => None,
    }
}

fn detect_protocol(renderer_override: Option<&str>) -> Protocol {
    // --renderer flag takes highest priority
    if let Some(name) = renderer_override {
        if let Some(p) = parse_renderer(name) {
            return p;
        }
        eprintln!(
            "Unknown renderer '{}'. Valid: kitty, iterm2, sixel, ansi",
            name
        );
        process::exit(1);
    }

    // IDIFF_RENDERER supersedes the upstream IMGAP_RENDERER spelling.
    for var in ["IDIFF_RENDERER", "IMGAP_RENDERER"] {
        if let Ok(val) = env::var(var)
            && let Some(p) = parse_renderer(&val)
        {
            return p;
        }
    }

    let in_tmux = env::var("TMUX").is_ok();

    // Outside tmux, environment names identify the real terminal directly.
    if !in_tmux {
        if let Ok(tp) = env::var("TERM_PROGRAM") {
            let tp = tp.to_lowercase();
            if tp.contains("kitty") || tp == "ghostty" {
                return Protocol::Kitty;
            }
            if tp == "iterm.app" || tp == "wezterm" {
                return Protocol::Iterm2;
            }
        }

        if let Ok(term) = env::var("TERM")
            && (term.contains("kitty") || term.contains("ghostty"))
        {
            return Protocol::Kitty;
        }

        if env::var("KITTY_WINDOW_ID").is_ok() {
            return Protocol::Kitty;
        }

        if let Ok(lc) = env::var("LC_TERMINAL")
            && lc == "iTerm2"
        {
            return Protocol::Iterm2;
        }
        if env::var("ITERM_SESSION_ID").is_ok() {
            return Protocol::Iterm2;
        }

        if env::var("WEZTERM_EXECUTABLE").is_ok() {
            return Protocol::Iterm2;
        }
    }

    // Inside tmux the pane runs under TERM=tmux-256color and hides the real
    // terminal. tmux's terminal emulation has no kitty graphics parser — raw
    // APC from the app never reaches the client — so capability detection
    // must go through tmux's own view of the attached client, and rendering
    // wraps every sequence in DCS passthrough (see write_kitty). tmux 3.7
    // refines client_termtype from device-attribute responses, e.g.
    // "ghostty 1.3.1".
    if in_tmux {
        let termtype = tmux_client_termtype().unwrap_or_default().to_lowercase();
        if termtype.contains("ghostty") || termtype.contains("kitty") {
            return Protocol::Kitty;
        }
    }

    // Probe for Sixel support via DA1 (Device Attributes) query.
    // This works both inside and outside tmux — tmux >= 3.4 will
    // report Sixel capability if its own support is enabled.
    if query_sixel_support() {
        return Protocol::Sixel;
    }

    Protocol::Ansi
}

/// Ask tmux what terminal is attached to the pane's client. Returns None
/// outside tmux or when tmux cannot answer.
fn tmux_client_termtype() -> Option<String> {
    if env::var("TMUX").is_err() {
        return None;
    }
    let output = Command::new("tmux")
        .args(["display-message", "-p", "#{client_termtype}"])
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    Some(String::from_utf8_lossy(&output.stdout).trim().to_string())
}

/// Read an image from disk. With the `svg` feature, paths ending in `.svg`
/// or `.svgz` are rasterized via resvg to fit within `max_w` x `max_h` so
/// downstream compare/render logic can treat them like any other bitmap.
struct ImageMeta {
    /// Display name like "PNG", "JPEG", "SVG", or "?" when undetectable.
    format: &'static str,
    width: u32,
    height: u32,
    size: u64,
}

fn read_meta(path: &str, img: &DynamicImage) -> ImageMeta {
    let size = std::fs::metadata(path).map(|m| m.len()).unwrap_or(0);
    let detected = image::ImageReader::open(path)
        .ok()
        .and_then(|r| r.with_guessed_format().ok())
        .and_then(|r| r.format());
    let format = format_name(detected).unwrap_or_else(|| {
        let lower = path.to_ascii_lowercase();
        if lower.ends_with(".svg") || lower.ends_with(".svgz") {
            "SVG"
        } else {
            "?"
        }
    });
    ImageMeta {
        format,
        width: img.width(),
        height: img.height(),
        size,
    }
}

fn format_name(fmt: Option<image::ImageFormat>) -> Option<&'static str> {
    Some(match fmt? {
        image::ImageFormat::Png => "PNG",
        image::ImageFormat::Jpeg => "JPEG",
        image::ImageFormat::Gif => "GIF",
        image::ImageFormat::WebP => "WebP",
        image::ImageFormat::Bmp => "BMP",
        image::ImageFormat::Tiff => "TIFF",
        image::ImageFormat::Ico => "ICO",
        image::ImageFormat::Hdr => "HDR",
        image::ImageFormat::OpenExr => "EXR",
        image::ImageFormat::Pnm => "PNM",
        image::ImageFormat::Dds => "DDS",
        image::ImageFormat::Tga => "TGA",
        image::ImageFormat::Farbfeld => "Farbfeld",
        image::ImageFormat::Avif => "AVIF",
        image::ImageFormat::Qoi => "QOI",
        _ => return None,
    })
}

fn format_size(bytes: u64) -> String {
    const KIB: f64 = 1024.0;
    const MIB: f64 = KIB * 1024.0;
    const GIB: f64 = MIB * 1024.0;
    let b = bytes as f64;
    if b >= GIB {
        format!("{:.1}GiB", b / GIB)
    } else if b >= MIB {
        format!("{:.1}MiB", b / MIB)
    } else if b >= KIB {
        format!("{:.1}KiB", b / KIB)
    } else {
        format!("{}B", bytes)
    }
}

/// Build a single-line summary like `PNG 1024x768→800x600 24.5KiB→18.3KiB`.
/// Each property is collapsed to a single value when both sides match
/// (e.g. same dimensions render as `1024x768` instead of `1024x768→1024x768`).
fn format_meta_line(a: &ImageMeta, b: &ImageMeta) -> String {
    let fmt = pair(a.format, b.format, |s| s.to_string());
    let dims = pair((a.width, a.height), (b.width, b.height), |(w, h)| {
        format!("{}x{}", w, h)
    });
    let size = pair(a.size, b.size, format_size);
    format!("{} {} {}", fmt, dims, size)
}

fn pair<T: PartialEq>(a: T, b: T, fmt: impl Fn(T) -> String) -> String {
    if a == b {
        fmt(a)
    } else {
        format!("{}→{}", fmt(a), fmt(b))
    }
}

fn draw_meta_line(w: &mut impl Write, cols: u16, row: u16, meta: &str) -> io::Result<()> {
    write!(w, "\x1b[{row};1H\x1b[2K")?;
    let width = meta.chars().count();
    let pad = (cols as usize).saturating_sub(width) / 2;
    if pad > 0 {
        write!(w, "\x1b[{}C", pad)?;
    }
    write!(w, "\x1b[2m{}\x1b[0m", meta)
}

fn load_image(path: &str, max_w: u32, max_h: u32) -> Result<DynamicImage, String> {
    #[cfg(feature = "svg")]
    {
        let p = std::path::Path::new(path);
        if svg::is_svg(p) {
            return svg::rasterize(p, max_w, max_h).map_err(|e| e.to_string());
        }
    }
    #[cfg(not(feature = "svg"))]
    let _ = (max_w, max_h);
    image::open(path).map_err(|e| e.to_string())
}

fn encode_png(img: &RgbaImage) -> Vec<u8> {
    let mut buf = Vec::new();
    let encoder = image::codecs::png::PngEncoder::new(&mut buf);
    img.write_with_encoder(encoder).expect("PNG encode failed");
    buf
}

fn write_kitty(img: &RgbaImage, w: &mut impl Write) -> io::Result<()> {
    let png_data = encode_png(img);
    let b64 = base64::Engine::encode(&base64::engine::general_purpose::STANDARD, &png_data);

    let chunk_size = 4096;
    let chunks: Vec<&str> = b64
        .as_bytes()
        .chunks(chunk_size)
        .map(|c| std::str::from_utf8(c).unwrap())
        .collect();

    // q=1 silences per-command acknowledgements; unsolicited responses would
    // otherwise land in the TUI's key stream.
    let mut stream: Vec<u8> = Vec::with_capacity(b64.len() + 64);
    for (i, chunk) in chunks.iter().enumerate() {
        let more = if i + 1 < chunks.len() { 1 } else { 0 };
        if i == 0 {
            write!(stream, "\x1b_Gf=100,a=T,q=1,m={};{}\x1b\\", more, chunk)?;
        } else {
            write!(stream, "\x1b_Gm={};{}\x1b\\", more, chunk)?;
        }
    }

    if env::var("TMUX").is_ok() {
        // tmux consumes APC graphics it cannot parse; DCS passthrough is the
        // only delivery path. ESC bytes inside the payload must be doubled.
        let mut wrapped = Vec::with_capacity(stream.len() + 16);
        wrapped.extend_from_slice(b"\x1bPtmux;");
        for &b in &stream {
            wrapped.push(b);
            if b == 0x1b {
                wrapped.push(0x1b);
            }
        }
        wrapped.extend_from_slice(b"\x1b\\");
        w.write_all(&wrapped)?;
    } else {
        w.write_all(&stream)?;
    }
    writeln!(w)?;
    w.flush()
}

/// Delete all kitty image placements, respecting the tmux passthrough rule.
fn kitty_clear_placements() -> Vec<u8> {
    if env::var("TMUX").is_ok() {
        b"\x1bPtmux;\x1b\x1b_Ga=d;\x1b\x1b\\\x1b\\".to_vec()
    } else {
        b"\x1b_Ga=d;\x1b\\".to_vec()
    }
}

fn write_iterm2(img: &RgbaImage, w: &mut impl Write) -> io::Result<()> {
    let png_data = encode_png(img);
    let b64 = base64::Engine::encode(&base64::engine::general_purpose::STANDARD, &png_data);

    write!(
        w,
        "\x1b]1337;File=inline=1;size={};width=auto;height=auto;preserveAspectRatio=1:{}\x07",
        png_data.len(),
        b64
    )?;
    writeln!(w)?;
    w.flush()
}

fn write_sixel(img: &RgbaImage, palette: &SixelPalette, w: &mut impl Write) -> io::Result<()> {
    let (width, height) = img.dimensions();

    // Build pixel-to-palette-index map via the palette's LUT (O(1) per pixel).
    let raw = img.as_raw();
    let n_pixels = (width * height) as usize;
    let mut indexed = vec![0u8; n_pixels];
    for (dst, chunk) in indexed.iter_mut().zip(raw.as_chunks::<4>().0) {
        *dst = palette.index(chunk[0], chunk[1], chunk[2]);
    }

    let num_bands = height.div_ceil(6) as usize;
    let palette_len = palette.colors.len();

    // Build sixel data into a buffer
    let mut buf = Vec::with_capacity(width as usize * height as usize);

    // Header
    // P2=1 selects transparent background; raster attributes set 1:1 aspect ratio
    write!(buf, "\x1bP0;1q\"1;1;{};{}", width, height)?;

    // Define colors
    for (i, &(r, g, b)) in palette.colors.iter().enumerate() {
        let rp = (r as u32 * 100) / 255;
        let gp = (g as u32 * 100) / 255;
        let bp = (b as u32 * 100) / 255;
        write!(buf, "#{};2;{};{};{}", i, rp, gp, bp)?;
    }

    // Scratch buffers reused across bands. `row_bufs[c][x]` holds the 6-bit
    // sixel value (not yet offset by 63) for color `c` at column `x` in the
    // current band. `used` marks which colors appear in the current band.
    let width_us = width as usize;
    let mut row_bufs: Vec<Vec<u8>> = (0..palette_len).map(|_| vec![0u8; width_us]).collect();
    let mut used: Vec<bool> = vec![false; palette_len];
    let mut used_list: Vec<u16> = Vec::with_capacity(palette_len);

    for band in 0..num_bands {
        let y_start = (band as u32) * 6;
        let y_end = (y_start + 6).min(height);

        // Reset only the colors that were dirty from the previous band.
        for &c in &used_list {
            used[c as usize] = false;
            // Zero only this color's row buffer; avoids touching all palette_len * width bytes.
            // Zero only this color's row buffer; avoids touching all
            // palette_len * width bytes every band.
            row_bufs[c as usize].fill(0);
        }
        used_list.clear();

        // Single pass over pixels in the band.
        for y in y_start..y_end {
            let bit = 1u8 << (y - y_start);
            let row_base = (y as usize) * width_us;
            let row = &indexed[row_base..row_base + width_us];
            for x in 0..width_us {
                let c = row[x] as usize;
                if !used[c] {
                    used[c] = true;
                    used_list.push(c as u16);
                }
                row_bufs[c][x] |= bit;
            }
        }

        for &c in &used_list {
            let color_idx = c as usize;
            buf.push(b'#');
            write!(buf, "{}", color_idx)?;

            let row = &row_bufs[color_idx];
            // RLE compress directly from the row buffer, adding 63 to form sixel chars.
            let mut i = 0;
            while i < row.len() {
                let sv = row[i];
                let mut count = 1usize;
                while i + count < row.len() && row[i + count] == sv {
                    count += 1;
                }
                let ch = sv + 63;
                if count >= 3 {
                    write!(buf, "!{}{}", count, ch as char)?;
                } else {
                    for _ in 0..count {
                        buf.push(ch);
                    }
                }
                i += count;
            }
            buf.push(b'$');
        }
        buf.push(b'-');
    }

    // End sixel stream
    buf.extend_from_slice(b"\x1b\\");

    w.write_all(&buf)?;
    writeln!(w)?;
    w.flush()
}

/// Render image as colored Unicode half-block characters (▄).
/// Each terminal row encodes two pixel rows: background color for the top pixel,
/// foreground color for the bottom pixel.
fn write_text(img: &RgbaImage, left_pad: u32, w: &mut impl Write) -> io::Result<()> {
    let (width, height) = img.dimensions();

    for (row, y) in (0..height).step_by(2).enumerate() {
        // Row 0's cursor column is set by the caller; later rows start at
        // column 1 after the row-ending \r\n, so shift them right to match.
        if left_pad > 0 && row > 0 {
            write!(w, "\x1b[{}C", left_pad)?;
        }
        for x in 0..width {
            let top = img.get_pixel(x, y);
            let bottom = if y + 1 < height {
                img.get_pixel(x, y + 1)
            } else {
                top
            };

            let (tr, tg, tb) = blend_alpha_rgb(top);
            let (br, bg, bb) = blend_alpha_rgb(bottom);

            // ESC[48;2;R;G;Bm = background (top pixel)
            // ESC[38;2;R;G;Bm = foreground (bottom pixel)
            write!(w, "\x1b[48;2;{tr};{tg};{tb}m\x1b[38;2;{br};{bg};{bb}m▄")?;
        }
        // Use an explicit CR+LF — in raw mode OPOST is off, so a bare \n
        // would only move the cursor down and leave the column where the
        // last glyph landed, skewing every other row.
        write!(w, "\x1b[0m\r\n")?;
    }
    w.flush()
}

/// Blend RGBA pixel against a black background, returning opaque RGB.
fn blend_alpha_rgb(pixel: &Rgba<u8>) -> (u8, u8, u8) {
    let a = pixel[3] as f32 / 255.0;
    (
        (a * pixel[0] as f32) as u8,
        (a * pixel[1] as f32) as u8,
        (a * pixel[2] as f32) as u8,
    )
}

/// 5 bits per channel → 32×32×32 = 32768-entry LUT (~32 KiB).
/// Each LUT entry stores the index of the palette color closest to the
/// bucket's midpoint. Accurate enough for a 255-color palette.
const SIXEL_LUT_BITS: u32 = 5;
const SIXEL_LUT_SHIFT: u32 = 8 - SIXEL_LUT_BITS;
const SIXEL_LUT_LEN: usize = 1 << (SIXEL_LUT_BITS * 3);

struct SixelPalette {
    colors: Vec<(u8, u8, u8)>,
    lut: Box<[u8]>,
}

impl SixelPalette {
    fn from_samples(samples: Vec<(u8, u8, u8)>, max_colors: usize) -> Self {
        // Median cut.
        let mut buckets: Vec<Vec<(u8, u8, u8)>> = vec![samples];
        while buckets.len() < max_colors {
            let mut best_idx = 0;
            let mut best_range = 0u32;
            for (i, bucket) in buckets.iter().enumerate() {
                if bucket.len() < 2 {
                    continue;
                }
                let range = channel_range(bucket);
                if range > best_range {
                    best_range = range;
                    best_idx = i;
                }
            }
            if best_range == 0 {
                break;
            }
            let bucket = buckets.swap_remove(best_idx);
            let (a, b) = split_bucket(bucket);
            if !a.is_empty() {
                buckets.push(a);
            }
            if !b.is_empty() {
                buckets.push(b);
            }
        }

        let colors: Vec<(u8, u8, u8)> = buckets
            .iter()
            .filter(|b| !b.is_empty())
            .map(|bucket| {
                let (mut sr, mut sg, mut sb) = (0u64, 0u64, 0u64);
                for &(r, g, b) in bucket {
                    sr += r as u64;
                    sg += g as u64;
                    sb += b as u64;
                }
                let n = bucket.len() as u64;
                ((sr / n) as u8, (sg / n) as u8, (sb / n) as u8)
            })
            .collect();

        // Build LUT: for each quantized RGB bucket midpoint, find nearest palette color.
        let mut lut = vec![0u8; SIXEL_LUT_LEN].into_boxed_slice();
        let bins = 1u32 << SIXEL_LUT_BITS;
        let half = 1i32 << (SIXEL_LUT_SHIFT - 1);
        for rb in 0..bins {
            let rr = ((rb << SIXEL_LUT_SHIFT) as i32 + half).min(255);
            for gb in 0..bins {
                let gg = ((gb << SIXEL_LUT_SHIFT) as i32 + half).min(255);
                for bb in 0..bins {
                    let bbv = ((bb << SIXEL_LUT_SHIFT) as i32 + half).min(255);
                    let mut best = 0u8;
                    let mut best_d = i32::MAX;
                    for (i, &(pr, pg, pb)) in colors.iter().enumerate() {
                        let dr = rr - pr as i32;
                        let dg = gg - pg as i32;
                        let db = bbv - pb as i32;
                        let d = dr * dr + dg * dg + db * db;
                        if d < best_d {
                            best_d = d;
                            best = i as u8;
                        }
                    }
                    let li = ((rb << (2 * SIXEL_LUT_BITS)) | (gb << SIXEL_LUT_BITS) | bb) as usize;
                    lut[li] = best;
                }
            }
        }

        Self { colors, lut }
    }

    fn from_images(imgs: &[&RgbaImage], max_colors: usize) -> Self {
        Self::from_samples(sample_pixels(imgs, 10_000), max_colors)
    }

    #[inline]
    fn index(&self, r: u8, g: u8, b: u8) -> u8 {
        let ri = (r as usize) >> SIXEL_LUT_SHIFT;
        let gi = (g as usize) >> SIXEL_LUT_SHIFT;
        let bi = (b as usize) >> SIXEL_LUT_SHIFT;
        let li = (ri << (2 * SIXEL_LUT_BITS)) | (gi << SIXEL_LUT_BITS) | bi;
        self.lut[li]
    }
}

/// Evenly sample at most `max_per_image` pixels from each input image.
fn sample_pixels(imgs: &[&RgbaImage], max_per_image: usize) -> Vec<(u8, u8, u8)> {
    let mut out = Vec::new();
    for img in imgs {
        let total = (img.width() * img.height()) as usize;
        if total == 0 {
            continue;
        }
        let step = if total > max_per_image {
            total / max_per_image
        } else {
            1
        };
        let raw = img.as_raw();
        let mut off = 0;
        while off < total {
            let base = off * 4;
            out.push((raw[base], raw[base + 1], raw[base + 2]));
            off += step;
        }
    }
    out
}

fn channel_range(pixels: &[(u8, u8, u8)]) -> u32 {
    let (mut rmin, mut rmax) = (255u8, 0u8);
    let (mut gmin, mut gmax) = (255u8, 0u8);
    let (mut bmin, mut bmax) = (255u8, 0u8);
    for &(r, g, b) in pixels {
        rmin = rmin.min(r);
        rmax = rmax.max(r);
        gmin = gmin.min(g);
        gmax = gmax.max(g);
        bmin = bmin.min(b);
        bmax = bmax.max(b);
    }
    let rd = (rmax - rmin) as u32;
    let gd = (gmax - gmin) as u32;
    let bd = (bmax - bmin) as u32;
    rd.max(gd).max(bd)
}

type Rgb = (u8, u8, u8);

fn split_bucket(mut pixels: Vec<Rgb>) -> (Vec<Rgb>, Vec<Rgb>) {
    let (mut rmin, mut rmax) = (255u8, 0u8);
    let (mut gmin, mut gmax) = (255u8, 0u8);
    let (mut bmin, mut bmax) = (255u8, 0u8);
    for &(r, g, b) in &pixels {
        rmin = rmin.min(r);
        rmax = rmax.max(r);
        gmin = gmin.min(g);
        gmax = gmax.max(g);
        bmin = bmin.min(b);
        bmax = bmax.max(b);
    }
    let rd = (rmax - rmin) as u32;
    let gd = (gmax - gmin) as u32;
    let bd = (bmax - bmin) as u32;

    if rd >= gd && rd >= bd {
        pixels.sort_unstable_by_key(|p| p.0);
    } else if gd >= bd {
        pixels.sort_unstable_by_key(|p| p.1);
    } else {
        pixels.sort_unstable_by_key(|p| p.2);
    }

    let mid = pixels.len() / 2;
    let b = pixels.split_off(mid);
    (pixels, b)
}
