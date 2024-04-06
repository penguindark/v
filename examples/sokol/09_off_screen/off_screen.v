/**********************************************************************
*
* Sokol off screen rendering demo
*
* Copyright (c) 2024 Dario Deledda. All rights reserved.
* Use of this source code is governed by an MIT license
* that can be found in the LICENSE file.
*
* HOW TO COMPILE SHADERS:
* Run `v shader .` in this directory to compile the shaders.
* For more info and help with shader compilation see `docs.md` and `v help shader`.
*
* TODO:
* 
**********************************************************************/
import gg
import gg.m4
import gx
import math
import sokol.gfx
// import sokol.sgl
import time

const win_width = 800
const win_height = 800
const bg_color = gx.white

struct App {
mut:
	gg          &gg.Context = unsafe { nil }
	texture     gfx.Image
	sampler     gfx.Sampler
	init_flag   bool
	frame_count int

	mouse_x    int = 903
	mouse_y    int = 638
	mouse_down bool

	// offscreen
	offscreen_pass gfx.Pass

	// glsl
	cube_pip_glsl gfx.Pipeline
	cube_bind     gfx.Bindings

	pipe map[string]gfx.Pipeline
	bind map[string]gfx.Bindings
	// time
	ticks i64
	
	// camera
	camera_x f32 = -8
	camera_z f32 = 47
}

/******************************************************************************
* Texture functions
******************************************************************************/
fn create_texture(w int, h int, buf byteptr) (gfx.Image, gfx.Sampler) {
	sz := w * h * 4
	// vfmt off
	mut img_desc := gfx.ImageDesc{
		width:         w
		height:        h
		num_mipmaps:   0
//		min_filter:    .linear
//		mag_filter:    .linear
		//usage: .dynamic
//		wrap_u:        .clamp_to_edge
//		wrap_v:        .clamp_to_edge
		label:         &u8(0)
		d3d11_texture: 0
	}
	// vfmt on
	// comment if .dynamic is enabled
	img_desc.data.subimage[0][0] = gfx.Range{
		ptr: buf
		size: usize(sz)
	}

	sg_img := gfx.make_image(&img_desc)

	mut smp_desc := gfx.SamplerDesc{
		min_filter: .linear
		mag_filter: .linear
		wrap_u: .clamp_to_edge
		wrap_v: .clamp_to_edge
	}

	sg_smp := gfx.make_sampler(&smp_desc)
	return sg_img, sg_smp
}

fn destroy_texture(sg_img gfx.Image) {
	gfx.destroy_image(sg_img)
}

// Use only if usage: .dynamic is enabled
fn update_text_texture(sg_img gfx.Image, w int, h int, buf byteptr) {
	sz := w * h * 4
	mut tmp_sbc := gfx.ImageData{}
	tmp_sbc.subimage[0][0] = gfx.Range{
		ptr: buf
		size: usize(sz)
	}
	gfx.update_image(sg_img, &tmp_sbc)
}

// create the offscreen render pipeline
fn offscreen_init(mut app App) {
	ws := gg.window_size_real_pixels()

	// resusable image description	
	mut img_desc := gfx.ImageDesc{
		render_target: true,
		width:         ws.width
		height:        ws.height
		num_mipmaps:   0
//		min_filter:    .linear
//		mag_filter:    .linear
		//usage: .dynamic
//		wrap_u:        .clamp_to_edge
//		wrap_v:        .clamp_to_edge
		pixel_format:  gfx.PixelFormat.rgba8, // SG_PIXELFORMAT_RGBA8
        sample_count:  1,
		label:         c'offscreen image'
		d3d11_texture: 0
	}

	// create colro buffer for offscreen
	sg_image_offscreen_color := gfx.make_image(&img_desc)

	// create depth buffer for offscreen
	img_desc.pixel_format = gfx.PixelFormat.depth // SG_PIXELFORMAT_DEPTH
	img_desc.sample_count = 1
    img_desc.label = c'depth-image'
    sg_image_depth_img := gfx.make_image(&img_desc)

    mut att_desc := gfx.AttachmentsDesc{
    	label: c'offscreen-attachments'
    }
	att_desc.colors[0] = gfx.AttachmentDesc{image: sg_image_offscreen_color}
 	att_desc.depth_stencil = gfx.AttachmentDesc{image:sg_image_depth_img}

 	offscreen_att := gfx.make_attachments(&att_desc)

 	app.offscreen_pass = gfx.Pass{
 		attachments: offscreen_att
 	}
}

/******************************************************************************
* Init / Cleanup
******************************************************************************/
fn my_init(mut app App) {
	// create chessboard texture 256*256 RGBA
	w := 256
	h := 256
	sz := w * h * 4
	tmp_txt := unsafe { malloc(sz) }
	mut i := 0
	for i < sz {
		unsafe {
			y := (i >> 0x8) >> 5 // 8 cell
			x := (i & 0xFF) >> 5 // 8 cell
			// upper left corner
			if x == 0 && y == 0 {
				tmp_txt[i + 0] = u8(0xFF)
				tmp_txt[i + 1] = u8(0)
				tmp_txt[i + 2] = u8(0)
				tmp_txt[i + 3] = u8(0xFF)
			}
			// low right corner
			else if x == 7 && y == 7 {
				tmp_txt[i + 0] = u8(0)
				tmp_txt[i + 1] = u8(0xFF)
				tmp_txt[i + 2] = u8(0)
				tmp_txt[i + 3] = u8(0xFF)
			} else {
				col := if ((x + y) & 1) == 1 { 0xFF } else { 128 }
				tmp_txt[i + 0] = u8(col) // red
				tmp_txt[i + 1] = u8(col) // green
				tmp_txt[i + 2] = u8(col) // blue
				tmp_txt[i + 3] = u8(0xFF) // alpha
			}
			i += 4
		}
	}
	unsafe {
		app.texture, app.sampler = create_texture(w, h, tmp_txt)
		free(tmp_txt)
	}

	// offscreen init
	offscreen_init(mut app)

	// glsl
	//init_cube_glsl_i(mut app)
	app.init_flag = true
}

fn draw_start_glsl(app App) {
	if app.init_flag == false {
		return
	}

	ws := gg.window_size_real_pixels()
	// ratio := f32(ws.width) / ws.height
	// dw := f32(ws.width  / 2)
	// dh := f32(ws.height / 2)

	gfx.apply_viewport(0, 0, ws.width, ws.height, true)
}

fn draw_end_glsl(app App) {
	gfx.end_pass()
	gfx.commit()
}

fn frame(mut app App) {
	// clear
	mut color_action := gfx.ColorAttachmentAction{
		load_action: .clear
		clear_value: gfx.Color{
			r: 0.0
			g: 0.0
			b: 0.0
			a: 1.0
		}
	}
	mut pass_action := gfx.PassAction{}
	pass_action.colors[0] = color_action
	pass := gg.create_default_pass(pass_action)
	gfx.begin_pass(&pass)

	draw_start_glsl(app)
	//draw_cube_glsl_i(mut app)
	draw_end_glsl(app)
	app.frame_count++
}

/******************************************************************************
* events handling
******************************************************************************/
fn my_event_manager(mut ev gg.Event, mut app App) {
	if ev.typ == .mouse_down {
		app.mouse_down = true
	}
	if ev.typ == .mouse_up {
		app.mouse_down = false
	}
	if app.mouse_down == true && ev.typ == .mouse_move {
		app.mouse_x = int(ev.mouse_x)
		app.mouse_y = int(ev.mouse_y)
	}
	if ev.typ == .touches_began || ev.typ == .touches_moved {
		if ev.num_touches > 0 {
			touch_point := ev.touches[0]
			app.mouse_x = int(touch_point.pos_x)
			app.mouse_y = int(touch_point.pos_y)
		}
	}

	// keyboard
	if ev.typ == .key_down {
		step := f32(1.0)
		match ev.key_code {
			.w { app.camera_z += step }
			.s { app.camera_z -= step }
			.a { app.camera_x -= step }
			.d { app.camera_x += step }
			else {}
		}
	}
	//eprintln('>> app.camera_x: ${app.camera_x} , app.camera_z: ${app.camera_z}, app.mouse_x: ${app.mouse_x}, app.mouse_y: ${app.mouse_y}')
}

fn main() {
	mut app := &App{}
	// vfmt off
	app.gg = gg.new_context(
		width:         win_width
		height:        win_height
		create_window: true
		window_title:  'Off screen rendering'
		user_data:     app
		bg_color:      bg_color
		frame_fn:      frame
		init_fn:       my_init
		event_fn:      my_event_manager
	)
	// vfmt on
	app.ticks = time.ticks()
	app.gg.run()
}