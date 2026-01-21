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
const tab_bg = gg.rgb(49, 50, 68)
// UI
const columns = ['Call count', 'Total time (ms)', 'Same w/o callee (ms)', 'Average duration (ns)',
	'Function Name']
const text_size = 20 // height
const text_line_h = text_size * 3 / 2
const rect_radius = text_size / 5
const max_handle_char = 20
const file_handle_w = text_size / 2 * max_handle_char + rect_radius
const file_bar_h = text_size * 3 / 2
const text_cfg = gg.TextCfg{
	color: text
	size:  text_size
}

struct ProcessFile {
	file_idx int
}

struct SortFile {
	file_idx   int
	column_idx int
}

@[heap]
struct App {
mut:
	ctx              &gg.Context = unsafe { nil }
	file_paths       []string
	file_lines       [][][]Data
	file_lines_max_l [][]int // max lenght of each column
	current_file     int
	scroll_y         int
	task_chan        chan Task = chan Task{cap: 100}
}

type Data = string | int | f32

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
		fullscreen:    true
		user_data:     app
		frame_fn:      on_frame
		event_fn:      on_event
		ui_mode:       true
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

	app.ctx.run()
	app.task_chan.close()
}

fn on_frame(mut app App) {
	s := app.ctx.window_size()
	app.ctx.begin()
	for i, fp in app.file_paths {
		app.ctx.draw_rounded_rect_filled(i * file_handle_w, 0, file_handle_w, file_bar_h +
			rect_radius, rect_radius, tab_handle)
		app.ctx.draw_text(i * file_handle_w + rect_radius / 2, file_bar_h / 3, fp#[fp.len - max_handle_char..],
			text_cfg)
	}
	app.ctx.draw_rect_filled(0, file_bar_h, s.width, s.height, tab_bg)
	if app.current_file >= app.file_lines.len {
		app.current_file = app.file_lines.len - 1
	}
	if app.current_file >= 0 {
		available_screen := s.height - file_bar_h
		if app.scroll_y > text_line_h * (app.file_lines[app.current_file].len + 3) - available_screen {
			app.scroll_y = text_line_h * (app.file_lines[app.current_file].len + 3) - available_screen
		}
		for j, fl in app.file_lines[app.current_file] {
			for i, lelem in fl {
				if i > 0 {
					app.ctx.draw_text(rect_radius +
						app.file_lines_max_l[app.current_file][i - 1] * text_size / 2,
						j * text_size - app.scroll_y, lelem, text_cfg)
				} else {
					app.ctx.draw_text(rect_radius, j * text_size - app.scroll_y, lelem,
						text_cfg)
				}
			}
		}
	} else {
		app.ctx.draw_text(s.width / 2 - no_file_opened.len * text_size / 4, s.height / 2,
			no_file_opened, text_cfg)
	}
	app.ctx.end()
}

fn on_event(e &gg.Event, mut app App) {
	match e.typ {
		.mouse_scroll {
			app.scroll_y += e.scroll_y
		}
		else {}
	}
}

fn task_processor(mut app App) {
	for {
		if select {
			task := <-app.task_chan {
				match mut task {
					ProcessFile {
						idx := app.file_lines.len
						app.file_lines << os.read_lines(app.file_paths[task.file_idx]) or {
							['The file was either empty or did not exist']
						}
						app.file_lines_max_l << [0, 0, 0, 0]
						if app.file_lines[idx].len > 1 { // If the file is not an error
							for mut l in app.file_lines[idx] {
								l = l.split_by_space()
								for l.len < columns.len {
									l << incomplete
								}
								l[0] = l[0].int()
								l[1] = l[1]#[..-2].f32()
								l[2] = l[2]#[..-2].f32()
								l[3] = l[3]#[..-2].int()
								app.file_lines_max_l[idx][0] = int_max(app.file_lines_max_l[idx][0],
									l[0].len)
								app.file_lines_max_l[idx][1] = int_max(app.file_lines_max_l[idx][1],
									l[1].len)
								app.file_lines_max_l[idx][2] = int_max(app.file_lines_max_l[idx][2],
									l[2].len)
								app.file_lines_max_l[idx][3] = int_max(app.file_lines_max_l[idx][3],
									l[3].len)
							}
						}
					}
					SortFile {
						if task.column_idx < columns.len {
							app.file_lines[task.file_idx].sort_with_compare(fn [task] (mut _a []Data, mut _b []Data) int {
								a := _a[task.column_idx]
								b := _b[task.column_idx]
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
			else {
				time.sleep(1 * time.millisecond)
			}
		} {
		} else {
			break // channel was closed
		}
	}
}
