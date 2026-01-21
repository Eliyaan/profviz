import os
import time
import flag
import gg

const version = '0.0.1'
const usage_example = 'profviz [profile]*'
const application = 'profviz - a gui profile visualizer written in V'
const incomplete = 'Incomplete'
const no_file_opened = 'No file opened'
// palette
const background = gg.rgb(30, 30, 46)
const text = gg.rgb(205, 214, 244)
const tab_handle = gg.rgb(69, 71, 90)
const tab_handle_selected = gg.rgb(88, 91, 112)
const tab_bg = gg.rgb(49, 50, 68)
const delimiter = gg.rgb(108, 112, 134)
const total_time_bar = gg.rgb(137, 180, 250)
const wo_callee_time_bar = gg.rgb(250, 179, 135)
// UI
const columns = ['Call count', 'Total time (ms)', 'Same w/o callee (ms)', 'Average duration (ns)',
	'Function Name']
const text_size = 20 // height
const scroll_bar_w = text_size
const text_line_h = text_size * 3 / 2
const rect_radius = text_size / 2
const max_handle_char = 20
const file_handle_w = text_size / 2 * max_handle_char + rect_radius
const file_bar_h = text_size * 3 / 2
const text_cfg = gg.TextCfg{
	color: text
	size:  text_size
}
const line_cfg = gg.TextCfg{
	color: text
	size:  text_size
	align: .right
}

struct ProcessFile {
	file_idx int
}

struct SortFile {
	file_idx   int
	column_idx int
}

enum Order {
	asc
	desc
}

@[heap]
struct App {
mut:
	ctx                   &gg.Context = unsafe { nil }
	file_paths            []string
	file_lines            [][][]Data
	file_lines_sort_order [][]Order
	file_lines_max_l      [][]int // max lenght of each column
	file_lines_max_t      []f32   // max time found
	current_file          int
	scroll_y              int
	task_chan             chan Task = chan Task{cap: 100}
}

type Data = string | int | f32

fn (d Data) str() string {
	return match d {
		string { d }
		int { d.str() }
		f32 { d.str() }
	}
}

type Task = ProcessFile | SortFile

fn main() {
	mut fp := flag.new_flag_parser(os.args)
	fp.skip_executable()
	fp.application(application)
	fp.usage_example(usage_example)
	fp.version(version)

	mut app := &App{}
	app.ctx = gg.new_context(
		create_window: true
		window_title:  'Profviz'
		user_data:     app
		frame_fn:      on_frame
		event_fn:      on_event
		sample_count:  4
		bg_color:      background
	)

	app.file_paths = fp.finalize() or {
		eprintln(err)
		println(fp.usage())
		exit(1)
	}
	for idx, _ in app.file_paths {
		app.task_chan <- ProcessFile{idx}
	}

	spawn task_processor(mut app)
	app.ctx.run()
	app.task_chan.close()
}

@[live]
fn on_frame(mut app App) {
	s := app.ctx.window_size()
	app.ctx.begin()
	if app.current_file >= app.file_lines.len {
		app.current_file = app.file_lines.len - 1
	}
	for i, fp in app.file_paths {
		if i == app.current_file {
			app.ctx.draw_rounded_rect_filled(i * file_handle_w, 0, file_handle_w - rect_radius / 4,
				file_bar_h + rect_radius, rect_radius, tab_handle_selected)
		} else {
			app.ctx.draw_rounded_rect_filled(i * file_handle_w, 0, file_handle_w - rect_radius / 4,
				file_bar_h + rect_radius, rect_radius, tab_handle)
		}
		app.ctx.draw_text(i * file_handle_w + rect_radius / 2, file_bar_h / 4, fp#[fp.len - max_handle_char..],
			text_cfg)
	}
	app.ctx.draw_rect_filled(0, file_bar_h, s.width, s.height, tab_bg)
	if app.current_file >= 0 {
		available_screen := s.height - file_bar_h
		available_screen_info := s.height - file_bar_h - text_line_h + rect_radius / 2
		scroll_max_y := text_line_h * (app.file_lines[app.current_file].len + 3) - (available_screen / text_line_h * text_line_h)
		scroll_bar_h := available_screen_info * available_screen_info / (app.file_lines[app.current_file].len * text_line_h)
		scroll_bar_y :=
			available_screen_info * app.scroll_y / (app.file_lines[app.current_file].len * text_line_h) +
			file_bar_h + text_line_h - rect_radius / 2
		app.ctx.draw_rect_filled(s.width - scroll_bar_w, scroll_bar_y, scroll_bar_w, scroll_bar_h,
			delimiter)
		if app.scroll_y > scroll_max_y {
			app.scroll_y = scroll_max_y
		}
		mut c_offset_x := 0
		for i, c in columns {
			c_offset_x += app.file_lines_max_l[app.current_file][i] * text_size / 2
			app.ctx.draw_text(rect_radius + c_offset_x, file_bar_h + rect_radius / 2,
				c, line_cfg)
			app.ctx.draw_line(c_offset_x + text_size, file_bar_h, c_offset_x + text_size,
				s.height, delimiter)
		}
		app.ctx.draw_line(0, file_bar_h + text_line_h - rect_radius / 2, c_offset_x +
			2 * rect_radius, file_bar_h + text_line_h - rect_radius / 2, delimiter)
		for j, fl in app.file_lines[app.current_file] {
			y := file_bar_h + (j + 1) * text_line_h - app.scroll_y
			if y >= file_bar_h + text_size && y <= s.height {
				mut offset_x := 0
				for i, lelem in fl {
					off_x_inc := app.file_lines_max_l[app.current_file][i] * text_size / 2
					offset_x += off_x_inc
					app.ctx.draw_text(rect_radius + offset_x, y, lelem.str(), line_cfg)
					if i == 1 && lelem is f32 {
						fact := lelem / app.file_lines_max_t[app.current_file]
						length := fact * (off_x_inc - text_size)
						app.ctx.draw_rect_filled(rect_radius + offset_x - length, y + text_size,
							length, 2, total_time_bar)
					} else if i == 2 && lelem is f32 {
						fact := lelem / app.file_lines_max_t[app.current_file]
						length := fact * (off_x_inc - text_size)
						app.ctx.draw_rect_filled(rect_radius + offset_x - length, y + text_size,
							length, 2, wo_callee_time_bar)
					}
				}
			}
		}
	} else {
		app.ctx.draw_text(s.width / 2 - no_file_opened.len * text_size / 4, s.height / 2,
			no_file_opened, text_cfg)
		if app.file_lines.len > 0 {
			app.current_file = 0
		}
	}
	app.ctx.end()
}

@[live]
fn on_event(e &gg.Event, mut app App) {
	match e.typ {
		.mouse_up {
			if app.current_file >= 0 && app.current_file < app.file_lines.len {
				if e.mouse_y > file_bar_h && e.mouse_y <= file_bar_h + text_size {
					mut c_offset_x := 0
					for i, _ in columns {
						c_offset_x += app.file_lines_max_l[app.current_file][i] * text_size / 2
						if e.mouse_x < c_offset_x {
							app.task_chan <- SortFile{app.current_file, i}
							return
						}
					}
				}
			}
			if e.mouse_y >= 0 && e.mouse_y <= file_bar_h {
				for i, _ in app.file_paths {
					if e.mouse_x < (i + 1) * file_handle_w {
						app.current_file = i
						return
					}
				}
			}
		}
		.mouse_scroll {
			app.scroll_y -= int(e.scroll_y) * text_line_h
			if app.scroll_y < 0 {
				app.scroll_y = 0
			}
		}
		else {}
	}
}

fn task_processor(mut app App) {
	for {
		if select {
			task := <-app.task_chan {
				match task {
					ProcessFile {
						idx := app.file_lines.len
						app.file_lines << (os.read_lines(app.file_paths[task.file_idx]) or {
							['The file was either empty or did not exist']
						}).map([Data(it)])
						app.file_lines_max_l << []int{len: columns.len}
						app.file_lines_sort_order << []Order{len: columns.len}
						app.file_lines_max_t << 0
						if app.file_lines[idx].len > 1 { // If the file is not an error
							for mut l in app.file_lines[idx] {
								l = (l[0] as string).split_by_space().map(Data(it))
								for l.len < columns.len {
									l << incomplete
								}
								for i, mut max in app.file_lines_max_l[idx] {
									max = int_max(max, (l[i] as string).len)
								}
								l[0] = (l[0] as string).int()
								l[1] = (l[1] as string)#[..-2].f32()
								app.file_lines_max_t[idx] = f32_max(app.file_lines_max_t[idx],
									l[1] as f32)
								l[2] = (l[2] as string)#[..-2].f32()
								l[3] = (l[3] as string)#[..-2].int()
							}
							for i, mut max in app.file_lines_max_l[idx] {
								max = int_max(max, columns[i].len)
							}
						}
					}
					SortFile {
						if task.file_idx >= 0 && task.file_idx < app.file_lines.len {
							if task.column_idx < columns.len {
								old_order := app.file_lines_sort_order[task.file_idx][task.column_idx]
								app.file_lines_sort_order[task.file_idx][task.column_idx] = if old_order == .asc {
									Order.desc
								} else {
									Order.asc
								}
								order := app.file_lines_sort_order[task.file_idx][task.column_idx]
								app.file_lines[task.file_idx].sort_with_compare(fn [task, order] (mut _a []Data, mut _b []Data) int {
									a := if order == .asc {
										_a[task.column_idx]
									} else {
										_b[task.column_idx]
									}
									b := if order == .asc {
										_b[task.column_idx]
									} else {
										_a[task.column_idx]
									}
									if a is int && b is int {
										if a < b {
											return -1
										}
										if a > b {
											return 1
										}
									}
									if a is string && b is string {
										if a < b {
											return -1
										}
										if a > b {
											return 1
										}
									}
									if a is f32 && b is f32 {
										if a < b {
											return -1
										}
										if a > b {
											return 1
										}
									}
									return 0
								})
							}
						}
					}
				}
			}
			else {
				time.sleep(1 * time.millisecond)
			}
		} {
		} else {
			break // channel was closed
		}
	}
}
