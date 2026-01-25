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
	file_path string
}

struct PfData {
mut:
	file_lines [][]string
	sort_order []Order
	max_l      []int
	max_t      f32
}

struct SortFile {
	file_idx   int // sent back to know which file to update
	file_lines [][]string
	column_idx int
	order      Order
}

struct SfData {
	file_idx   int
	file_lines [][]string
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
	file_lines            [][][]string
	file_lines_sort_order [][]Order
	file_lines_max_l      [][]int // max lenght of each column
	file_lines_max_t      []f32   // max time found
	current_file          int
	scroll_y              int
	pf_chan               chan ProcessFile = chan ProcessFile{cap: 100}
	pf_data_chan          chan PfData      = chan PfData{cap: 100}
	sf_chan               chan SortFile    = chan SortFile{cap: 100}
	sf_data_chan          chan SfData      = chan SfData{cap: 100}
}

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
		ui_mode:       true
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

	spawn task_processor(app.pf_chan, app.pf_data_chan, app.sf_chan, app.sf_data_chan)

	for f in app.file_paths {
		app.pf_chan <- ProcessFile{f}
	}

	app.ctx.run()
	app.pf_chan.close()
	app.pf_data_chan.close()
	app.sf_chan.close()
	app.sf_data_chan.close()
}

fn on_frame(mut app App) {
	select {
		pf_data := <-app.pf_data_chan {
			app.file_lines << pf_data.file_lines
			app.file_lines_sort_order << pf_data.sort_order
			app.file_lines_max_l << pf_data.max_l
			app.file_lines_max_t << pf_data.max_t
		}
		sf_data := <-app.sf_data_chan {
			app.file_lines[sf_data.file_idx] = sf_data.file_lines
		}
		else {}
	}
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
					app.ctx.draw_text(rect_radius + offset_x, y, lelem, line_cfg)
					if i == 1 {
						fact := lelem.f32() / app.file_lines_max_t[app.current_file]
						length := fact * (off_x_inc - text_size)
						app.ctx.draw_rect_filled(rect_radius + offset_x - length, y + text_size,
							length, 2, total_time_bar)
					} else if i == 2 {
						fact := lelem.f32() / app.file_lines_max_t[app.current_file]
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

fn on_event(e &gg.Event, mut app App) {
	match e.typ {
		.mouse_up {
			if app.current_file >= 0 && app.current_file < app.file_lines.len {
				if e.mouse_y > file_bar_h && e.mouse_y <= file_bar_h + text_size {
					mut c_offset_x := 0
					for i, _ in columns {
						c_offset_x += app.file_lines_max_l[app.current_file][i] * text_size / 2
						if e.mouse_x < c_offset_x + text_size {
							old_order := app.file_lines_sort_order[app.current_file][i]
							app.file_lines_sort_order[app.current_file][i] = if old_order == .asc {
								Order.desc
							} else {
								Order.asc
							}
							order := app.file_lines_sort_order[app.current_file][i]
							app.sf_chan <- SortFile{app.current_file, app.file_lines[app.current_file], i, order}
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

fn task_processor(pf_chan chan ProcessFile, pf_data_chan chan PfData, sf_chan chan SortFile, sf_data_chan chan SfData) {
	for {
		if select {
			task := <-pf_chan {
				mut pf_data := PfData{}
				raw_file_lines := os.read_lines(task.file_path) or { continue }
				pf_data.max_l = []int{len: columns.len}
				pf_data.sort_order = []Order{len: columns.len}
				pf_data.max_t = 0
				for line in raw_file_lines {
					mut l := line.split_by_space()
					if l.len != columns.len {
						continue
					}
					for i, mut max in pf_data.max_l {
						max = int_max(max, l[i].len)
					}
					total_time := l[1].f32()
					pf_data.max_t = f32_max(pf_data.max_t, total_time)
					pf_data.file_lines << l
				}
				for i, mut max in pf_data.max_l {
					max = int_max(max, columns[i].len)
				}
				pf_data_chan <- pf_data
			}
			task := <-sf_chan {
				if task.column_idx < columns.len {
					sf_data_chan <- SfData{task.file_idx, task.file_lines.sorted_with_compare(fn [task] (mut aaa []string, mut bbb []string) int {
						aa := if task.order == .asc {
							aaa[task.column_idx]
						} else {
							bbb[task.column_idx]
						}
						bb := if task.order == .asc {
							bbb[task.column_idx]
						} else {
							aaa[task.column_idx]
						}
						if task.column_idx == 0 || task.column_idx == 3 {
							a := aa.int()
							b := bb.int()
							if a < b {
								return -1
							}
							if a > b {
								return 1
							}
						}
						if task.column_idx == 4 {
							if aa < bb {
								return -1
							}
							if aa > bb {
								return 1
							}
						}
						if task.column_idx == 1 || task.column_idx == 2 {
							a := aa.f32()
							b := bb.f32()
							if a < b {
								return -1
							}
							if a > b {
								return 1
							}
						}
						return 0
					})}
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
