import os
import flag
import gg

const version = '0.0.1'
const usage_example = 'profviz [profile]*'
const application = 'profviz - a gui profile visualizer written in V'
// palette
const background = gg.rgb(30, 30, 46)
const text = gg.rgb(205, 214, 244)
const tab_handle = gg.rgb(69, 71, 90)
const tab_bg = gg.rgb(49, 50, 68)
// UI
const columns = ['Call count', 'Total time (ms)', 'Same w/o callee (ms)', 'Average duration (ns)', 'Function Name'] 
const text_size = 20
const rect_radius = text_size / 5
const file_bar_h = text_size * 3 / 2
const text_cfg = gg.TextCfg{color: text, size: text_size}

struct ProcessFile {
	file_idx int
}

struct SortFile {
	file_idx int
	column_idx int
}

@[heap]
struct App {
	ctx &gg.Context = unsafe {nil}
	file_paths []string
	file_lines [][]Data
	task_chan chan Task = chan Task{cap: 100}
}

type Data = string | int | f32

type Task = ProcessFiles | SortFile

fn main() {
	mut fp := flag.new_flag_parser(os.args)
	fp.skip_executable()
	fp.application(application)
	fp.usage_example(usage_example)
	fp.version(version)

	mut app := &App{}
        app.ctx = gg.new_context(
                create_window: true
		window_title: 'Profviz'
                fullscreen: true
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

        app.ctx.run()
	app.task_chan.close()
}

fn on_frame(mut app App) {
	app.ctx.begin()
	
	app.ctx.end()
}

fn on_event(e &gg.Event, mut app App) {
//	match e.typ {
//	}
}

fn task_processor(mut app App) {
	for {
		if select {
			task := <- app.task_chan {
				match mut task {
					ProcessFile {
						idx := app.file_lines.len
						app.file_lines << os.read_lines(app.file_paths[task.file_idx]) or {['The file was either empty or did not exist']}
						if app.file_lines[idx].len > 1 { // If the file is not an error
							for mut l in app.file_lines[idx] {
								l = l.split_by_space()
								for l.len < columns.len {
									l << 'Incomplete'
								}
								l[0] = l[0].int()
								l[1] = l[1]#[..-2].f32()
								l[2] = l[2]#[..-2].f32()
								l[3] = l[3]#[..-2].int()
							}
						}
					}
					SortFile {
						if task.column_idx < columns.len {
							app.file_lines[task.file_idx].sort_with_compare(fn [task] (_a &string, _b &string) int {
								a := _a[task.column_idx]
								b := _b[task.column_idx]
								if a is int && b is int || a is string && b is string || a is f32 && b is f32{
									if a[task.column_idx] < b[task.column_idx] {
										return -1
									}
									if a[task.column_idx] > b[task.column_idx] {
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

