; --------------------------------
; "Castle Master 2: The Crypt" by Incentive Software Ltd., 1990
; Disassembled by Santiago Ontañón in 2023
;
; Disclaimer: All the comments, label and constant names in this disassembly are my best interpretation of what the
;   code actually does. Fully annotating a disassembly like this one requires a large amount of work (this one took
;   me over a month, dedicating 2-3 hours every day). Therefore, it might contain errors or misunderstandings.
;   Please report if you find something that is incorrect. When I am very unsure of what some code does, I added
;   a note, but I might have missed many.
; 
; Notes and curiosities from the codebase:
; - There are two identical functions:
;   - La9de_hl_eq_h_times_64
;   - Lcb6d_hl_eq_h_times_64
; - There are two implemented versions of the same multiplication operation "(de,hl) = de * hl":
;   - La15e_de_times_hl_signed
;   - L8ab4_de_times_hl_signed
;   - Interestingly: the first is redundant, since the second is smaller and faster. However, it is the
;     first that is the most commonly used in the code!!!
; - There is self-modifying code
; - The 3d rendering engine is quite advanced for the year it was written:
;   - It contains all basic elements of later 3d engines
;   - It only considers 2 rotation angles (pitch and yaw), but it would be trivial to add a third, if it
;       wasn't because of the skybox (which would have to rotate if we added "roll").
;   - It contains skybox rendering code for outdoor areas (and even a "lightning" animation over the skybox!)
;   - It supports textured shapes
;   - Objects can be lines, triangles, quads or pentagons
;   - It implements many levels of culling (quick rendering cube, rendering frustum/pyramid)
;   - It implements polygon clipping for those that are only partly within the screen
;   - Different stages of rendering are "cached" in memory, so that we do not need to repeat them. For example,
;     when entering a menu, and going back to the game, all the 3d -> 2d projection does not need to be redone,
;     as positions have not changed. So, this is skipped. Similarly, when player does not move, rotation matrices
;     are not recalculated.
;   - All in all, even if the individual functions are not very optimized (things can be done significantly faster),
;     the overall structure is very nice (and some of the low-level functions are indeed quite optimized, such as
;     the one that renders textured horizontal lines).
; - All the computations are done with fixed point arithmetic. Even line and polygon drawing uses this fixed-point
;   calculations, rather than the more optimized Bresenham routines. This makes the code simpler, even if
;   slower than it could be.
; - Sorting of objects for rendering is quite curious, as it happens in coordinates *before* they are projected to
;   camera coordinates (just distance from player in each separate axis). I am sure this causes many issues in corner
;   cases. 
; - I think the code has a couple of bugs, I marked them with "BUG?" tags. Of course, I am not 100% sure, but I
;   think they are bugs.
; 
; Potential optimization of the code:
; - The code seems more functional than optimized. The lowest level drawing routines seem to be optimized well, but most
;   of the math routines are not. So, there is a lot of opportunity to make the engine faster.
; - I have added "OPTIMIZATION" tags in places where small things could be optimized. I only added those that
;   an automatic optimizer (in this case MDL: https://github.com/santiontanon/mdlz80optimizer) would not already
;   detect automatically. Basically, these are notes for an potential optimized version. Only small things are noted
;   large architectural changes (like moving from fixed-point arithmetic line-drawing to Bresenham-style, are not
;   annotated in the code).
;
; Related work:
; - See Phantasma, a reimplementation of the Freescape engine: https://github.com/TomHarte/Phantasma
; - See the information on the Freescape reimplementation in SCUMMVM: https://wiki.scummvm.org/index.php?title=Freescape
;

; --------------------------------
; BIOS Functions and constants:
; - Information obtained from "The Spectrum Machine Code Reference Guide" book.

; Saves a collection of bytes to tape
; Input:
; - ix: address to save
; - de: byte count
L04c6_BIOS_CASSETTE_SAVE_NO_BREAK_TEST: equ #04c6

; Loads a collection of bytes from tape
; Input:
; - ix: address where to load
; - de: byte count
L0562_BIOS_READ_FROM_TAPE_SKIP_TESTS: equ #0562

ULA_PORT: equ #fe  ; Writing to this port ignores the high 8bits.
                   ; The 8 bit value written is used as follows:
                   ; - bits 0, 1, 2: border color
                   ; - bit 3: MIC (tape output)
                   ; - bit 4: speaker output


; --------------------------------
; Video memory constants:
; - Information obtained from: http://www.breakintoprogram.co.uk/hardware/computers/zx-spectrum/screen-memory-layout
L4000_VIDEOMEM_PATTERNS: equ #4000
L5800_VIDEOMEM_ATTRIBUTES: equ #5800

SCREEN_WIDTH: equ 24
SCREEN_HEIGHT: equ 14
SCREEN_WIDTH_IN_PIXELS: equ SCREEN_WIDTH * 8  ; 192
SCREEN_HEIGHT_IN_PIXELS: equ SCREEN_HEIGHT * 8  ; 112

; --------------------------------
; Game constants:
CONTROL_MODE_KEYBOARD: equ 0
CONTROL_MODE_SINCLAIR_JOYSTICK: equ 1
CONTROL_MODE_KEMPSTON_JOYSTICK: equ 2
CONTROL_MODE_CURSOR_JOYSTICK: equ 3

MAX_COORDINATE: equ 127*64

MAX_PRESSED_KEYS: equ 5
FILENAME_BUFFER_SIZE: equ 12

SPIRIT_METER_MAX: equ 64
MAX_STRENGTH: equ 24

GAME_OVER_REASON_OVERPOWERED: equ 1
GAME_OVER_REASON_YOU_COLLAPSE: equ 2
GAME_OVER_REASON_CRUSHED: equ 3
GAME_OVER_REASON_FATAL_FALL: equ 4
GAME_OVER_REASON_ESCAPED: equ 5

; Sound FX:
SFX_MENU_SELECT: equ 3  ; Also used for when player collides with an object
SFX_THROW_ROCK_OR_LAND: equ 5
SFX_FALLING: equ 6
SFX_GAME_START: equ 7
SFX_LIGHTNING: equ 8
SFX_GATE_CLOSE: equ 9
SFX_PICK_UP_ITEM: equ 10
SFX_OPEN_CHEST: equ 11
SFX_CLIMB_DROP: equ 12
SFX_OPEN_ESCAPED: equ 13
; There are other SFX defined, but only used in the game scripts:
; 1  ; sounds like if you die / get hit / error
; 2  ; sounds like game over
; 4  ; short high -> higher pitch beep
; 14  ; low-pitch repeated sound, not sure what
; 15  ; tiny short SFX

INPUT_FORWARD: equ 3
INPUT_BACKWARD: equ 4
INPUT_TURN_LEFT: equ 5
INPUT_TURN_RIGHT: equ 6
INPUT_LOOK_UP: equ 7
INPUT_LOOK_DOWN: equ 8
INPUT_CRAWL: equ 9
INPUT_WALK: equ 10
INPUT_RUN: equ 11
INPUT_FACE_FORWARD: equ 12
INPUT_U_TURN: equ 13

INPUT_MOVEMENT_POINTER_ON_OFF: equ 21
INPUT_THROW_ROCK: equ 22
INPUT_MOVE_POINTER_RIGHT: equ 23
INPUT_MOVE_POINTER_LEFT: equ 24
INPUT_MOVE_POINTER_DOWN: equ 25
INPUT_MOVE_POINTER_UP: equ 26
INPUT_ACTION: equ 27

INPUT_SWITCH_BETWEEN_MOVEMENT_AND_POINTER: equ 30

INPUT_INFO_MENU: equ 41

; How many degrees is a full circle:
FULL_ROTATION_DEGREES: equ 72

; Datablock structures:
AREA_HEADER_SIZE: equ 8

; Area struct:
AREA_FLAGS: equ 0
AREA_N_OBJECTS: equ 1
AREA_ID: equ 2
AREA_RULES_OFFSET: equ 3  ; 2 bytes
AREA_SCALE: equ 5
AREA_ATTRIBUTE: equ 6
AREA_NAME: equ 7

; Object struct:
OBJECT_TYPE_AND_FLAGS: equ 0
OBJECT_X: equ 1
OBJECT_Y: equ 2
OBJECT_Z: equ 3
OBJECT_SIZE_X: equ 4
OBJECT_SIZE_Y: equ 5
OBJECT_SIZE_Z: equ 6
OBJECT_ID: equ 7
OBJECT_SIZE: equ 8
OBJECT_ADDITIONAL_DATA: equ 9

; Object types:
OBJECT_TYPE_ENTRANCE: equ 0
OBJECT_TYPE_CUBE: equ 1
OBJECT_TYPE_SPIRIT: equ 2
OBJECT_TYPE_RECTANGLE: equ 3
; - Object types in between 4 and 9 are different solids, like pyramids,
; hourglasses, wedges, etc. that are synthesized on the fly.
; - I believe the object ID here just indicates their orientation (one of
; the 6 possible cardinal directions in 3d), and their additional data
; is used to determine their exact shape (via some checks in at the bedinning of
; function "L97bb_project_other_solids").
OBJECT_TYPE_LINE: equ 10
OBJECT_TYPE_TRIANGLE: equ 11
OBJECT_TYPE_QUAD: equ 12
OBJECT_TYPE_PENTAGON: equ 13
OBJECT_TYPE_HEXAGON: equ 14

; Rule types:
RULE_TYPE_ADD_TO_SCORE: equ 1
RULE_TYPE_TOGGLE_OBJECT_VISIBILITY: equ 3
RULE_TYPE_MAKE_OBJECT_VISIBILE: equ 4
RULE_TYPE_MAKE_OBJECT_INVISIBILE: equ 5
RULE_TYPE_TOGGLE_OBJECT_FROM_AREA_VISIBILITY: equ 6
RULE_TYPE_MAKE_OBJECT_FROM_AREA_VISIBILE: equ 7
RULE_TYPE_MAKE_OBJECT_FROM_AREA_INVISIBILE: equ 8
RULE_TYPE_INCREMENT_VARIABLE: equ 9
RULE_TYPE_DECREMENT_VARIABLE: equ 10
RULE_TYPE_END_RULE_IF_VARIABLE_DIFFERENT: equ 11
RULE_TYPE_SET_BOOLEAN_TRUE: equ 12
RULE_TYPE_SET_BOOLEAN_FALSE: equ 13
RULE_TYPE_END_RULE_IF_BOOLEAN_DIFFERENT: equ 14
RULE_TYPE_PLAY_SFX: equ 15
RULE_TYPE_DESTROY_OBJECT: equ 16
RULE_TYPE_DESTROY_OBJECT_FROM_AREA: equ 17
RULE_TYPE_TELEPORT: equ 18
RULE_TYPE_STRENGTH_UPDATE: equ 19
RULE_TYPE_SET_VARIABLE: equ 20
RULE_TYPE_REDRAW: equ 26
RULE_TYPE_PAUSE: equ 27
RULE_TYPE_REQUEST_SFX_NEXT_FRAME: equ 28
RULE_TYPE_TOGGLE_BOOLEAN: equ 29
RULE_TYPE_END_RULE_IF_OBJECT_INVISIBLE: equ 30
RULE_TYPE_END_RULE_IF_OBJECT_VISIBLE: equ 31
RULE_TYPE_END_RULE_IF_OBJECT_FROM_AREA_INVISIBLE: equ 32
RULE_TYPE_END_RULE_IF_OBJECT_FROM_AREA_VISIBLE: equ 33
RULE_TYPE_SHOW_MESSAGE: equ 34
RULE_TYPE_RENDER_EFFECT: equ 35
RULE_TYPE_FLIP_SKIP_RULE: equ 44
RULE_TYPE_UNSET_SKIP_RULE: equ 45
RULE_TYPE_END_RULE_IF_VARIABLE_LARGER: equ 46
RULE_TYPE_END_RULE_IF_VARIABLE_LOWER: equ 47
RULE_TYPE_SELECT_OBJECT: equ 48


; --------------------------------
; RAM Variables before the game data:
L5cbc_render_buffer: equ #5cbc  ; 2712 bytes ((SCREEN_HEIGHT * 8 + 1) * SCREEN_WIDTH)

; Variables that overlap with the render buffer, these are used when projecting
; the 3d vertices into 2d, so, they are discarded and not needed when using the 
; render buffer.
L5e4c_pitch_rotation_matrix: equ #5e4c
L5e55_rotation_matrix: equ #5e55
L5e5e_at_least_one_vertex_outside_rendering_frustum: equ #5e5e
L5e5f_add_to_projected_objects_flag: equ #5e5f  ; If this is 1, the current object being projected from 3d to 2d, will be added to the list of objects to draw.
L5e60_projection_pre_work_type: equ #5e60  ; Indicates whether we need to do additional computations before projecting each face.
L5e61_object_currently_being_processed_type: equ #5e61
L5e62_player_collision_with_object_flags: equ #5e62
L5e63_3d_vertex_coordinates_relative_to_player: equ #5e63
L5e75_48_bit_accumulator: equ #5e75
L5e7b_48bitmul_tmp1: equ #5e7b
L5e7d_48bitmul_tmp2: equ #5e7d

L5e9f_3d_vertex_coordinates_after_rotation_matrix: equ #5e9f  ; 16 bit representation.

L5edc_vertex_rendering_frustum_checks: equ #5edc  ; 5 bits per vertex, indicating if they passed or not each of the 5 culling tests for the rendering frustum.

L5ee8_already_projected_vertex_coordinates: equ #5ee8

L5f24_shape_edges_ptr: equ #5f24  ; Pointer to the array with the order of edges to use for projection.
L5f26_alternative_shape_edges_ptr: equ #5f26  ; Alternative edges pointer (for when object is seen from below, this is only needed for flat shapes).
L5f28_cull_face_when_no_projected_vertices: equ #5f28
L5f29_extra_solid_dimensions: equ #5f29  ; stores 4 additional dimensions used temporarily to synthesize solids like pyramids, hourglasses, etc. on the fly. (4 16bit numbers).
L5f31_sorting_comparison_result: equ #5f31  ; result of comparing the coordinates of two objects to see if they should be flipped for rendering.
L5f32_sorting_any_change: equ #5f32
L5f33_sorting_boundingbox_ptr1: equ #5f33
L5f35_sorting_boundingbox_ptr2: equ #5f35
L5f37_sorting_bbox1_c1: equ #5f37  ; These four variables hold the values of the min/max coordinates for the current axis of the two bounding boxes being compared for sorting.
L5f39_sorting_bbox2_c1: equ #5f39
L5f3b_sorting_bbox1_c2: equ #5f3b
L5f3d_sorting_bbox2_c2: equ #5f3d
L5f3f_n_objects_covering_the_whole_screen_left: equ #5f3f
L5f40_16_bit_tmp_matrix: equ #5f40  ; Used internally to save the results of matrix multiplication.
L5f52_16_bit_tmp_matrix_ptr: equ #5f52  ; Used to keep track of the elements in the matrix above.

L5fa2_3d_object_bounding_boxes_relative_to_player: equ #5fa2  ; in 16 bit precision: x1, x2, y1, y2, z1, z2

L6664_row_pointers: equ #6664  ; Pointers to each row of pixels in the buffer.
L6754_end_of_render_buffer: equ #6754

; This contains the current room objects, already projected to 2d coordinates:
; - Each entry has 2 pointers:
;   - One pointer to the "L67f4_projected_vertex_data" (with the projected vertices)
;   - One pointer to the "L5fa2_3d_object_bounding_boxes_relative_to_player"
L6754_current_room_object_projected_data: equ #6754

; For each projected object, the data is organized as follows:
; - 1 byte: object ID
; - 1 byte: number of primitives/faces:
;   - If the most significant bit is set, it means this object covers the whole screen.
; - face data:
;   - 1 byte (texture / # vertices),
;   - and then 2 bytes per vertex screen x, screen y (screen y is reversed, 0 = bottom).
L67f4_projected_vertex_data: equ #67f4


    org #6a00

; --------------------------------
; Program start
L6a00_start:
    jp L6a2f_game_init


; --------------------------------
; Set up the interrupt routine to "Lbe66_interrupt_routine".
L6a03_setup_interrupts:
    di
    push hl
    push de
    push bc
    push af
        xor a
        ld (L747c_within_interrupt_flag), a
        ld hl, Lfe00_interrupt_vector_table
        ld a, h
        ld i, a
        ld d, h
        ld e, l
        inc e
        ld (hl), #fd
        ld bc, 256
        ldir
        ld a, #c3  ; jp opcode
        ld hl, Lbe66_interrupt_routine
        ld (Lfdfd_interrupt_jp), a
        ld (Lfdfe_interrupt_pointer), hl
        im 2
    pop af
    pop bc
    pop de
    pop hl
    ei
    ret


; --------------------------------
; Initializes the game the very first time.
L6a2f_game_init:
    ld sp, #fff8  ; initialize the stack
    di
    xor a  ; Set control mode to keyboard
    ld (L7683_control_mode), a
    ld (L747d), iy  ; Note: This instruction is very strange, as at this point "iy" is undefined.
    call La4c9_init_game_state
    call L6a03_setup_interrupts
    jp L6a7e_main_application_loop


; --------------------------------
; Unused?
    db #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00
    db #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00
    db #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00
    db #00, #00, #00, #00, #00, #00, #00, #00, #00, #00


; --------------------------------
; Main application loop: calls title screen, starts game, restarts title screen, etc.
; I think this is a game loop
L6a7e_main_application_loop:
    ld hl, #fffd
    ld (L746c_game_flags), hl
    ld a, 2
    ld (L7477_render_buffer_effect), a  ; Request gate opening effect
    call Lc72e_title_screen_loop
    call L83aa_redraw_whole_screen
    xor a
    ld (L7479_current_game_state), a
    jp L6a99
L6a96_game_loop:
    call L83aa_redraw_whole_screen
L6a99:
    call L9dec_game_tick
    call La005_check_rules
    ld hl, (L746c_game_flags)
    bit 1, l  ; check the "game over" flag
    jp z, L6a96_game_loop
    call La4c9_init_game_state
    jp L6a7e_main_application_loop


; --------------------------------
; Game state variables:
; Saving game saves data starting from here:
L6aad_savegame_data_start:
L6aad_player_current_x:
    dw #00a0
L6aaf_player_current_y:
    dw #09e0
L6ab1_player_current_z:
    dw #1b60
L6ab3_current_speed_in_this_room:
    dw #11d0
L6ab5_current_speed:  ; This is a value form the Ld0c8_speed_when_crawling array, depending on L6b0b_selected_movement_mode.
    db #f0
L6ab6_player_pitch_angle:  ; from 18 to -18 (54)
    db #00
L6ab7_player_yaw_angle:  ; from 0 - 71
    db #1a
L6ab8_player_crawling:  ; 2 when standing up, 1 when crawling.
    db 2
L6ab9_player_height:  ; player height * room scale
    db #26
L6aba_max_falling_height_without_damage:  ; 2 * room scale
    db #26
L6abb_max_climbable_height:
    db #13
L6abc_current_room_scale:
    db #13
L6abd_cull_by_rendering_volume_flag:
    db #00
L6abe_use_eye_player_coordinate:  ; When this is 0, we will use "feet" coordinates for collision checks, when 1, we will use "eye" coordinates.
    db #00
L6abf_current_area_name_string:
    db 0, "   THE CRYPT   "
L6acf_current_area_id:
    db #02
L6ad0_current_area_n_objects:
    db #18
L6ad1_current_area_objects:
    dw #d6ca

    db #00, #00  ; unused?
L6ad5_current_area_rules:
    dw #d8ce
L6ad7_current_border_color:
    db #14, #00
L6ad9_current_attribute_color:
    db #16, #0b
L6adb_desired_border_color:
    db #14, #00
L6add_desired_attribute_color:
    db #47, #0b
L6adf_game_boolean_variables:
    ; One bit corresponding to each variable. 
    ; The first few correspond to collected keys.
    db #00, #00, #00, #00
L6ae3_visited_areas:  ; one bit per area (keeps track of which areas the player has already visited).
    db #00, #00, #00, #00, #00, #00, #00, #00
L6aeb_score:  ; 3 bytes
    db #00, #00, #00
L6aee_game_variables:  ; These can be accessed by the game scripts.
    db #00, #00, #00, #00, #00, #00, #00, #00
    db #00, #00, #00, #00, #00, #00, #00, #00
    db #00, #00, #00, #00, #00, #00, #00, #00
    db #00, #00, #00
L6b09_number_of_spirits_destroyed:
    db 0
L6b0a_current_strength:
    db 16
L6b0b_selected_movement_mode:  ; 0: crawl, 1: walk, 2: run
    db 2
L6b0c_num_collected_keys:
    db 0
L6b0d_new_key_taken: 
    db 0  ; Contains the ID of a key just picked up, before being added to the inventory.
L6b0e_lightning_time_seconds_countdown:
    db #14
L6b0f_collected_keys:
    ; Different from "L6adf_game_boolean_variables", this array has the keys in
    ; the order the player picked them, directly as a list of IDs.
    db #00, #00, #00, #00, #00, #00, #00, #00, #00, #00
L6b19_current_area_flags:
    db #00
L6b1a_pointer_x:
    db 0
L6b1b_pointer_y:
    db 0
L6b1c_movement_or_pointer:
    db 0  ; 0: movement, otherwise: pointer
L6b1d_time_interrupts:
    db #01
L6b1e_time_unit5:  ; Changes once per second, counting from 10 to 1
    db #00
L6b1f_current_spirit_meter:  ; Increments in 1 each time Lbe65_time_unit3 wraps around (each 120 seconds).
    db #20
L6b20_display_movement_pointer_flag:  ; Whether to draw a small cross in the center of the screen when in movement mode.
    db #ff
L6b21_time_unit6_previous:  ; to keep track of when L6b22_time_unit6 changes.
    db #00
L6b22_time_unit6:  ; Increments by one each time L6b1e_time_unit5 cycles.
    db #00
L6b23_set_bit7_byte_3_flag_at_start:  ; If this is != 0, when starting a game, bit 7 of the 3rd byte of the boolean variables is set to 1 (not sure of the effect of this).
    db #00
L6b24_savegame_data_end:

    db #00, #00, #07, #00  ; Unused?
L6b28_player_radius:
    dw #000a
L6b2a_spirit_in_room:  ; 0: no spirit, 1: spirit
    db 0
L6b2b_desired_eye_compass_frame:
    db #00

; If an object definition has more bytes than this, it means there are rule effects associated with it:
L6b2c_expected_object_size_by_type:
    db #09, #0c, #0e, #0a, #10, #10, #10, #10, #10, #10, #10, #13, #16, #19, #1c, #00

L6b3c_rule_size_by_type:  ; Assuming there are only 49 rule types (maximum type if 48).
    db #01, #04, #02, #02, #02, #02, #03, #03, #03, #02, #02, #03, #02, #02, #03, #02
    db #02, #03, #03, #02, #03, #00, #00, #00, #00, #02, #01, #02, #02, #02, #02, #02
    db #03, #03, #02, #02, #00, #00, #00, #00, #00, #02, #01, #00, #01, #01, #03, #03
    db #02

; Edges for cubes:
L6b6d_cube_edges:
    db #0c
    db #00, #01, #01, #02, #02, #03, #03, #00
    db #04, #05, #05, #06, #06, #07, #07, #04
    db #00, #04, #01, #05, #02, #06, #03, #07

; byte 0: number of faces
; Each face then:
; - byte: texture
; - byte: number of vertices/edges
; - bytes 2+: edge indexes from where to get the vertices
; - the msb in the index indicates if we need to flip the vertexes in the edge in question.
L6b86_face_definition_for_cubes:
    db #06
    db #00, #04, #83, #0b, #07, #88
    db #00, #04, #05, #8a, #81, #09
    db #00, #04, #08, #04, #89, #80
    db #00, #04, #0a, #06, #8b, #82
    db #00, #04, #00, #01, #02, #03
    db #00, #04, #84, #87, #86, #85

; Edges for pyramids:
L6bab_pyramid_edges:
    db #08
    db #00, #01, #01, #02, #02, #03, #03, #00
    db #00, #04, #01, #04, #02, #04, #03, #04

L6bbc_face_definition_for_pyramids:
    db #05
    db #00, #03, #83, #07, #84
    db #00, #03, #82, #06, #87
    db #00, #03, #81, #05, #86
    db #00, #03, #80, #04, #85
    db #00, #04, #00, #01, #02, #03

L6bd7_wedge_edges:
    db #09
    db #00, #01, #01, #02, #02, #03
    db #03, #00, #00, #04, #01, #04
    db #02, #05, #03, #05, #04, #05

L6bea_face_definition_for_wedges:
    db #05
    db #00, #04, #83, #07, #88, #84
    db #00, #03, #82, #06, #87
    db #00, #04, #81, #05, #08, #86
    db #00, #03, #80, #04, #85
    db #00, #04, #00, #01, #02, #03

L6c07_triangle_houglass_edges:
    db #09
    db #00, #01, #01, #02, #02, #03
    db #03, #00, #00, #04, #01, #05
    db #02, #05, #03, #04, #04, #05

L6c1a_face_definition_for_triangle_hourglasses:
    db #05
    db #00, #03, #83, #07, #84
    db #00, #04, #82, #06, #88, #87
    db #00, #03, #81, #05, #86
    db #00, #04, #80, #04, #08, #85
    db #00, #04, #00, #01, #02, #03

L6c37_hourglass_edges:
    db #0c
    db #00, #01, #01, #02, #02, #03, #03, #00
    db #04, #07, #07, #05, #05, #06, #06, #04
    db #00, #04, #01, #06, #02, #05, #03, #07

L6c50_face_definition_for_hourglasses:
    db #06
    db #00, #04, #83, #0b, #84, #88
    db #00, #04, #82, #0a, #85, #8b
    db #00, #04, #81, #09, #86, #8a
    db #00, #04, #80, #08, #87, #89
    db #00, #04, #00, #01, #02, #03
    db #00, #04, #04, #05, #06, #07

; Edge definition for different shapes (lines, triangles, rectangles and pentagons),
; - the first byte is the # of edges
; - after that, each pair of bytes defines an edge.
L6c75_line_edges:
    db #02, #00, #01, #01, #00

; Edges for triangles:
L6c7a_triangle_edges_top:
    db #03, #00, #01, #01, #02, #02, #00
L6c81_triangle_edges_bottom:
    db #03, #00, #02, #02, #01, #01, #00

; Edges for rectangles:
L6c88_rectangle_edges_top:
    db #04, #00, #01, #01, #02, #02, #03, #03, #00
L6c91_rectangle_edges_bottom:
    db #04, #00, #03, #03, #02, #02, #01, #01, #00

; Edges for pentagons:
L6c9a_pentagon_edges_top:
    db #05, #00, #01, #01, #02, #02, #03, #03, #04, #04, #00
L6ca5_pentagon_edges_bottom:
    db #05, #00, #04, #04, #03, #03, #02, #02, #01, #01, #00

L6cb0_face_definition_for_flat_objects:
    db #01
    db #00, #06, #00, #01, #02, #03, #04, #05


; --------------------------------
L6cb9_game_text:
    db 0, " PRESS ANY KEY "
L6cc9_text_overpowered:
    db 0, "  OVERPOWERED  "
    db 1, " YOU COLLAPSE  "
    db 0, "    CRUSHED    "
    db 1, "  FATAL FALL   "
    db 0, "   ESCAPE !!   "
    db 0, "   THE CRYPT   "
L6d29_text_out_of_reach:
    db 1, " OUT OF REACH  "
L6d39_text_no_effect:
    db 0, "   NO EFFECT   "
    db 1, "   NO ENTRY    "
    db 0, "  WAY BLOCKED  "
L6d69_text_not_enough_room:
    db 0, "NOT ENOUGH ROOM"
L6d79_text_too_weak:
    db 1, "   TOO WEAK    "
L6d89_text_crawl:
    db 1, "CRAWL SELECTED "
L6d99_text_walk:
    db 0, " WALK SELECTED "
L6da9_text_run:
    db 1, " RUN SELECTED  "
    db 1, " AAAAAARRRGH!  "
    db 0, " KEY COLLECTED "
    db 0, " NO KEYS FOUND "
    db 1, "NEED RIGHT KEY "
    db 0, "  IT IS EMPTY  "
    db 1, "  DOOR TO...   "
    db 0, "IN CASE OF FIRE"
    db 0, "CHOMP CHOMP AHH"
    db 1, "   OOOOFFF!    "
    db 1, "TREASURE FOUND "
    db 1, "THE DOOR OPENS "
    db 0, "THE DOOR CLOSES"
    db 0, "   PADLOCKED   "
    db 0, "IT'S VERY HEAVY"
    db 0, "    SMASH !    "
    db 0, "SHOWS LEVEL NO."
    db 0, "   PADLOCKED   "
    db 0, "HMM, NEED A BIT"
    db 1, "MORE SPRING IN "
    db 1, "YOUR STEP HERE "
    db 0, " THE LID OPENS "
    db 1, "THE LID CLOSES "
    db 1, "GLUG GLUG GLUG "
    db 0, "RETRY THE CHEST"
    db 1, "REVITALISATION "
L6f49_area_names:
    db 1, "  WILDERNESS   "
    db 0, "   THE CRYPT   "
    db 1, "CRYPT CORRIDOR "
    db 0, " THE MOUSETRAP "
    db 0, " LAST TREASURE "
    db 1, "   TANTALUS    "
    db 0, "    BELENUS    "
    db 0, "    POTHOLE    "
    db 0, "   THE STEPS   "
    db 1, " LOOKOUT POST  "
    db 1, "   KERBEROS    "
    db 0, "   CRYPT KEY   "
    db 0, "   GATEHOUSE   "
    db 0, "  BELENUS KEY  "
    db 1, "SPIRITS' ABODE "
    db 1, "    RAVINE     "
    db 1, "  LIFT SHAFT   "
    db 0, "  LEVEL 2 KEY  "
    db 0, "LIFT ENTRANCE 6"
    db 1, "    TUNNEL     "
    db 0, "  LEVEL 3 KEY  "
    db 1, "   THE TUBE    "
    db 0, "LIFT ENTRANCE 5"
    db 0, "     EPONA     "
    db 0, "  LEVEL 4 KEY  "
    db 0, "LIFT ENTRANCE 4"
    db 0, "  NANTOSUELTA  "
    db 0, "  STALACTITES  "
    db 0, "    NO ROOM    "
    db 0, "  THE TRAPEZE  "
    db 1, "TREASURE CHEST "
    db 0, "LIFT ENTRANCE 3"
    db 1, "  THE SWITCH   "
    db 1, "  THE PILLAR   "
    db 1, " GROUND FLOOR  "
    db 1, " THE RAT TRAP  "
    db 0, "    YIN KEY    "
    db 1, "     LIFT      "
    db 0, "  TRAPEZE KEY  "
    db 1, "   YANG KEY    "


; --------------------------------
L71c9_text_status_array:
    db 0, "FEEBLE    "
    db 0, "WEAK      "
    db 0, "HEALTHY   "
    db 0, "STRONG    "
    db 0, "MIGHTY    "
    db 0, "HERCULEAN "

; --------------------------------
; Used to store the filename the user inputs in the load/save menu.
L720b_text_input_buffer:
    db 0, "             "
    db 19  ; Unused?

L721a_text_asterisks:
    db 0, "*********************"

    db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    db #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #30, #72, #30, #72, #30
    db #72, #30, #72, #30, #72, #30, #72, #30, #72, #30, #72, #30, #72, #30, #72


; --------------------------------
L725c_videomem_row_pointers:
    dw #4084, #4184, #4284, #4384, #4484, #4584, #4684, #4784
    dw #40a4, #41a4, #42a4, #43a4, #44a4, #45a4, #46a4, #47a4
    dw #40c4, #41c4, #42c4, #43c4, #44c4, #45c4, #46c4, #47c4
    dw #40e4, #41e4, #42e4, #43e4, #44e4, #45e4, #46e4, #47e4
    dw #4804, #4904, #4a04, #4b04, #4c04, #4d04, #4e04, #4f04
    dw #4824, #4924, #4a24, #4b24, #4c24, #4d24, #4e24, #4f24
    dw #4844, #4944, #4a44, #4b44, #4c44, #4d44, #4e44, #4f44
    dw #4864, #4964, #4a64, #4b64, #4c64, #4d64, #4e64, #4f64
    dw #4884, #4984, #4a84, #4b84, #4c84, #4d84, #4e84, #4f84
    dw #48a4, #49a4, #4aa4, #4ba4, #4ca4, #4da4, #4ea4, #4fa4
    dw #48c4, #49c4, #4ac4, #4bc4, #4cc4, #4dc4, #4ec4, #4fc4
    dw #48e4, #49e4, #4ae4, #4be4, #4ce4, #4de4, #4ee4, #4fe4
    dw #5004, #5104, #5204, #5304, #5404, #5504, #5604, #5704
    dw #5024, #5124, #5224, #5324, #5424, #5524, #5624, #5724


; --------------------------------
; Unused?
L733c:
    db #30, #72, #30, #72, #30, #72, #30, #72, #30, #72
    db #30, #72, #30, #72, #30, #72, #30, #72, #30, #72

L7350_compass_eye_ui_row_pointers:
    ; from (25, 158) to (25, 162)    
    dw #5679, #5779, #5099, #5199, #5299

L735a_ui_message_row_pointers
    ; from (11, 176) to (11, 183)
    dw #50cb, #51cb, #52cb, #53cb
    dw #54cb, #55cb, #56cb, #57cb

L736a_spirit_count_ui_row_pointers:
    ; from (14, 152) to (14, 159)
    dw #506e, #516e, #526e, #536e
    dw #546e, #556e, #566e, #576e

L737a_strength_ui_row_pointers
    ; from (4, 151) to (4, 165)
    dw #5744, #5064, #5164, #5264
    dw #5364, #5464, #5564, #5664
    dw #5764, #5084, #5184, #5284
    dw #5384, #5484, #5584

L7398_key_count_ui_row_pointers
    ; from (4, 173) to (4, 186)
    dw #55a4, #56a4, #57a4, #50c4
    dw #51c4, #52c4, #53c4, #54c4
    dw #55c4, #56c4, #57c4, #50e4
    dw #51e4, #52e4

L73b4_waving_flag_row_pointers:
    dw #451d, #461d, #471d, #403d
    dw #413d, #423d, #433d, #443d
    dw #453d

L73c6_cosine_sine_table:
    ; Each "dw" contains (cos, sin) (one byte each):
    ; [-64, 64]
    ; 72 steps is a whole turn.
    dw #4000, #4006, #3f0b, #3e11
    dw #3c16, #3a1b, #3720, #3425
    dw #3129, #2d2d, #2931, #2534
    dw #2037, #1b3a, #163c, #113e
    dw #0b3f, #0640, #0040, #fa40
    dw #f53f, #ef3e, #ea3c, #e53a
    dw #e037, #db34, #d731, #d32d
    dw #cf29, #cc25, #c920, #c61b
    dw #c416, #c211, #c10b, #c006
    dw #c000, #c0fa, #c1f5, #c2ef
    dw #c4ea, #c6e5, #c9e0, #ccdb
    dw #cfd7, #d3d3, #d7cf, #dbcc
    dw #e0c9, #e5c6, #eac4, #efc2
    dw #f5c1, #fac0, #00c0, #06c0
    dw #0bc1, #11c2, #16c4, #1bc6
    dw #20c9, #25cc, #29cf, #2dd3
    dw #31d7, #34db, #37e0, #3ae5
    dw #3cea, #3eef, #3ff5, #40fa

L7456_player_desired_x:
    dw 0
L7458_player_desired_y:
    dw 0
L745a_player_desired_z:
    dw 0
    db #00  ; Unused?
L745d_rendering_cube_volume:  ; max/min x, max/min y, max/min z (objects outside this will not be rendered).
    db #00, #00, #00, #00, #00, #00
L7463_global_area_objects:
    dw #d2c6
L7465_global_area_n_objects:
    db #4b

L7466_need_attribute_refresh_flag:
    db 1
L7467_player_starting_position_object_id:
    db #01
L7468_focus_object_id:
    db #01
L7469_n_spirits_found_in_current_area:
    db #00
L746a_current_drawing_texture_id:
    db #00
L746b_n_objects_to_draw:
    db #00
L746c_game_flags:
    db #fd, #ff ; 1st byte :
                ; - bit 0: ????
                ; - bit 1: game over indicator.
                ; - bit 2: indicates that we need to "reproject" 3d objects to the 2d viewport.
                ; - bit 3: ????
                ; - bit 4/5: trigger redraw of compass eye.
                ; - bit 6: ????
                ; - bit 7: ????
                ; 2nd byte: 
                ; - bit 0: ????
                ; - bit 1: ????
                ; - bit 2: ????
                ; - bit 3: trigger a re-render.
                ; - bit 4: flag to refresh spirit meter.
                ; - bit 5: in the update function, it triggers waiting until interrupt timer is 0, and then reprints the current room name.
                ; - bit 6: flag to refresh # of keys in UI.
                ; - bit 7: flag to redraw keys in the UI.
L746e_global_rules_ptr:
    dw #d11f
L7470_previous_area_id:  ; Set when a RULE_TYPE_TELEPORT is triggered, but it is unused.
    db #00
L7471_event_rule_found:  ; 1 indicates that a rule for the corresponding event was found (0 otherwise).
    db #00
L7472_symbol_shift_pressed:
    db 0  ; 0 = not pressed, 1 = pressed.
L7473_timer_event:  ; every time L6b22_time_unit6 changes, this is set to 8.
    db #00
L7474_check_if_object_crushed_player_flag:
    db #00
L7475_call_Lcba4_check_for_player_falling_flag:  ; Indicates whether we should call Lcba4_check_for_player_falling this game cycle.
    db #01
L7476_trigger_collision_event_flag:  ; If this is "1" after the player has tried to move, it means we collided with an object.
    db #00
L7477_render_buffer_effect:
    db #02
L7478_interrupt_executed_flag:  ; some methods use this to wait for the interrupt to be executed.
    db #01
L7479_current_game_state:
    ; This is:
    ; - 0: for when player is controlling
    ; - 1: some times game state is 1 even not at game over (e.g. before game starts).
    ; - 1-5: when game is over (and number identifies the reason, including successful escape!)
    ; - 6: for when in the load/save/quit menu
    db #01
L747a_requested_SFX:
    db #00
L747b:  ; Unused, set to 63 at game start, unused afterwards.
    db #3f
L747c_within_interrupt_flag:
    db 0  ; This is changed to #80 when we are inside the interrupt.

L747d:  ; Note: This saves the value of "iy" at game start, and restores it each time tape is accessed.
        ; But it makes no sense, as the tape load/save functions do not make use of iy. Very strange!
    dw #5c3a
L747f_player_event:  ; player events (they can be "or-ed"): 1: moving, 2: interact, 4: trow rock
    db #00
L7480_under_pointer_object_ID:  ; stores the ID of the object under the player pointer.
    db #00
L7481_n_objects_covering_the_whole_screen:
    db 0
; Copy of the projected vertex coordinates used by the Lb607_find_object_under_pointer
; function:
L7482_object_under_pointer__current_face_vertices:
    db #00, #00, #00, #00, #00, #00, #00, #00, #00, #00
    db #00, #00, #00, #00, #00, #00, #00, #00, #00, #00
L7496_current_drawing_primitive_n_vertices:
    db #00
L7497_next_projected_vertex_ptr:  ; initialized at 'L67f4_projected_vertex_data', and keeps increasing as we project objects from 3d to 2d.
    dw #0000
L7499_3d_object_bounding_box_relative_to_player_ptr:
    dw #0000
L749b_next_object_projected_data_ptr:
    dw #0000
L749d_object_currently_being_processed_ptr:
    dw #0000
L749f_number_of_pressed_keys:
    db #00
L74a0_pressed_keys_buffer:
    db #ef, #4e, #cd, #77, #66
L74a5_interrupt_timer:
    db #00  ; Decreases by 1 at each interrupt until reaching 0. It is used by the game to create pauses.
L74a6_player_movement_delta:
    dw #0000, #0000, #0000
; These two sets of coordinates are used to define the volume the player will traverse when moving.
; It is used because, due to the low frame rate, the player moves in very large steps, and we need
; to ensure small objects are not skipped.
L74ac_movement_volume_max_coordinate:
    dw #0000, #0000, #0000
L74b2_movement_volume_min_coordinate:
    dw #0000, #0000, #0000
; These 3 sets of coordinates are used in the "Lab6d_correct_player_movement_if_collision_internal"
; function to store the target movement position after correcting them in case there is a
; collision with an object.
L74b8_collision_corrected_coordinates_2:
    dw #0000, #0000, #0000
L74be_collision_corrected_climb_coordinates:
    dw #0000, #0000, #0000
L74c4_collision_corrected_coordinates_1:
    dw #0000, #0000, #0000
L74ca_movement_target_coordinates_2:  ; used when there is falling involved in movement
    dw #0000, #0000, #0000
L74d0_target_object_climb_coordinates:
    dw #0000  ; x
    dw #0000  ; y
    dw #0000  ; z
L74d6_movement_target_coordinates_1:  ; used when there is no falling involved in movement
    dw #0000, #0000, #0000
L74dc_falling_reference_coordinates:
    dw #0000, #0000, #0000
L74e2_movement_direction_bits:
    ; bit 0 means negative movement on x, bit 1 means positive movement on y
    ; bits 2, 3 the same for y, and 4, 5 the same for z.
    db #00
L74e3_player_height_16bits:  ; (L6ab9_player_height) * 64
    dw #0000
L74e5_collision_correction_object_shape_type:  ; the game prefers 3d shapes to 2d shapes when correcting movement upon collisions. This variable is used to implemetn such preference.
    db #00
L74e6_movement_involves_falling_flag:  ; 0: no falling, 1: we fell
    db #00
L74e7_closest_object_below_distance:
    dw #0000
L74e9_closest_object_below_ptr:
    dw #0000
L74eb_closest_object_below_ID:
    db #00
L74ec_previous_pressed_keys_buffer:
    db #16, #5e, #3a, #d6, #1f
L74f1:  ; Note: I believe this is unused (written, but never read)
    db #0e
L74f2_keyboard_input:  ; 8 bytes, one per keyboard half row
    db #00, #00, #00, #00, #00, #00, #00, #00

L74fa_object_under_pointer__current_face:  ; saves the pointer to the current face we are checking when trying to find which object is under the pointer.
    dw #0c67

L74fc_object_under_pointer__projected_xs_at_pointer_y:
    db #18  ; number of points in the lsit below
    db #f5, #c6, #30, #23, #77  ; screen x coordinates of face edges at the y coordinate of the pointer.
                                ; Used by the "Lb607_find_object_under_pointer" function, to determine
                                ; which object is under the player pointer.

; --------------------------------
; Rendering variables:
L7502_sp_tmp:  ; Used to temporarily save the 'sp' register.
    dw 0
L7504_line_drawing_slope:  ; Amount we need to move in the X axis each time we move one pixel in the Y axis.
    dw #0000               ; Uses fixed point arithmetic (with 8 bits of decimal part).
L7506_polygon_drawing_second_slope:  ; When drawing polygons, we calculate two lines at once, and draw 
    dw #0000                         ; horizontal lines between them. This is the slopw of the second line.
L7508_current_drawing_row:
    db #00
L7509_line_drawing_thinning_direction:
    db #00
L750a_first_loop_flags:  ; Used to indicate if we have drawn at least one pixel when drawing polygons.
    db #00
L750b_current_drawing_n_vertices_left:  ; How many vertices are there to draw in the current primitive.
    db 0
L750c_current_drawing_row_ptr:
    dw 0
L750e_current_drawing_texture_ptr:
    dw 0
L7510_current_drawing_2d_vertex_buffer:
    db #00, #00, #00, #00, #00, #00, #00, #00
    db #00, #00, #00, #00, #00, #00, #00, #00
    db #00, #00, #00, #00, #00, #00, #00, #00
    db #00, #00, #00, #00, #00, #00, #00, #00
    db #00, #00, #00, #00, #00, #00, #00, #00

; --------------------------------
L7538_text_spaces:
    db 0, "              "
L7547_text_play_record:
    db 0, "PLAY & RECORD,"
L7556_text_invalid_file:
    db 0, "INVALID FILE  "
L7565_text_loading_error:
    db 0, "LOADING ERROR "
L7574_text_loading:
    db 0, "LOADING :     "
L7583_text_then_any_key:
    db 0, "THEN ANY KEY  "
L7592_text_saving_file:
    db 0, "SAVING FILE   "
L75a1_text_found:
    db 0, "FOUND :       "
L75b0_text_searching:
    db 0, "SEARCHING     "

; --------------------------------
L75bf_SFX_table:
    db 30, #59, #00, #01  ; 30,  89 (dw), 1
    db 18, #47, #00, #01  ; 18,  71 (dw), 1
    db  1, #ef, #00, #01  ;  1, 239 (dw), 1
    db  9, #00, #03, #01  ;  9, 768 (dw), 1
    db  2, #00, #00, #01  ;  2,   0 (dw), 1
    db  8, #50, #00, #01  ;  8,  90 (dw), 1
    db 26, #00, #03, #03  ; 26, 768 (dw), 3
    db 11, #02, #00, #01  ; 11,   2 (dw), 1
    db 30, #59, #00, #01  ; ...
    db 13, #43, #00, #0c
    db 22, #f7, #09, #01
    db  0, #77, #00, #01
    db  4, #52, #01, #01
    db 28, #96, #00, #08
    db 16, #00, #00, #09
L75fb_SFX_data:
    db #01, #17, #01, #01
    db #01, #02, #81, #04
    db #81, #2e, #00, #01
    db #00, #14, #00, #00
    db #04, #02, #81, #10
    db #07, #ff, #0a, #34
    db #ff, #01, #06, #00
    db #02, #00, #00, #00
    db #01, #7f, #01, #03
    db #81, #4c, #00, #01
    db #00, #f6, #ff, #00
    db #81, #20, #00, #02
    db #00, #30, #00, #00
    db #03, #06, #00, #01
    db #04, #01, #02, #08
    db #ff, #01, #00, #00
    db #80, #07, #02, #00
    db #00, #00, #00, #00
    db #05, #02, #7f, #04
    db #02, #7f, #0a, #03
    db #7f, #0f, #06, #7f
    db #10, #06, #7f, #22
    db #04, #02, #81, #43
    db #04, #81, #0a, #08
    db #81, #0a, #05, #81
    db #09, #00, #00, #00
    db #81, #4c, #00, #01
    db #00, #fa, #ff, #00
    db #02, #04, #7f, #02
    db #04, #81, #04, #00
    db #04, #03, #7f, #03
    db #04, #7f, #05, #07
    db #7f, #06, #06, #00
    db #04, #00, #00, #00

L7683_control_mode:
    db #00  ; Current control mode:
            ; 0: keyboard
            ; 1: sinclair joystick
            ; 2: kempston joystick
            ; 3: cursor joystick


; --------------------------------
; Input mapping (table that assigns keys to game functions).
L7684_input_mapping:
    ; Each row has 3 values: (key, game function while in movement, game function while in pointer)
    db '7', INPUT_FORWARD, INPUT_MOVE_POINTER_UP
    db 'O', INPUT_FORWARD, INPUT_MOVE_POINTER_UP 
    db #91, INPUT_FORWARD, INPUT_MOVE_POINTER_UP
    db '6', INPUT_BACKWARD, INPUT_MOVE_POINTER_DOWN
    db 'K', INPUT_BACKWARD, INPUT_MOVE_POINTER_DOWN
    db #92, INPUT_BACKWARD, INPUT_MOVE_POINTER_DOWN
    db '5', INPUT_TURN_LEFT, INPUT_MOVE_POINTER_LEFT
    db 'Z', INPUT_TURN_LEFT, INPUT_MOVE_POINTER_LEFT
    db #93, INPUT_TURN_LEFT, INPUT_MOVE_POINTER_LEFT
    db '8', INPUT_TURN_RIGHT, INPUT_MOVE_POINTER_RIGHT
    db 'X', INPUT_TURN_RIGHT, INPUT_MOVE_POINTER_RIGHT
    db #94, INPUT_TURN_RIGHT, INPUT_MOVE_POINTER_RIGHT
    ; Each row has 2 values: (key, game function)
    db '0', INPUT_THROW_ROCK
    db #95, INPUT_THROW_ROCK
    db 'B', INPUT_MOVEMENT_POINTER_ON_OFF
    db 'C', INPUT_CRAWL
    db 'W', INPUT_WALK
    db 'R', INPUT_RUN
    db ' ', INPUT_SWITCH_BETWEEN_MOVEMENT_AND_POINTER
    db 'A', INPUT_ACTION
    db 'U', INPUT_U_TURN
    db 'F', INPUT_FACE_FORWARD
    db 'P', INPUT_LOOK_UP
    db 'L', INPUT_LOOK_DOWN
    db 'I', INPUT_INFO_MENU

; Temporary sprite attribute buffer for method Lcc19_draw_viewport_sprite_with_offset:
L76c2_buffer_sprite_x:
    db 0
L76c3_buffer_sprite_y:
    db 0
L76c4_buffer_sprite_width:
    db 0
L76c5_buffer_sprite_height:
    db 0
L76c6_buffer_sprite_ptr:
    dw #0000
L76c8_buffer_sprite_bytes_to_skip_at_start:
    db #00
    db #00  ; unused
L76ca_bytes_to_skip_after_row:
    db #00
    db #00  ; unused

L76cc_ui_key_bg_sprite:
    db 6, 14, #ff  ; width, height, and-mask
    dw 84  ; frame size
    db #63, #ff, #ff, #ff, #ff, #f8
    db #41, #ff, #ff, #ff, #ff, #f0
    db #41, #ff, #ff, #ff, #ff, #f0
    db #54, #00, #00, #00, #00, #05
    db #40, #00, #00, #00, #00, #00
    db #55, #55, #55, #55, #55, #55
    db #41, #ff, #ff, #ff, #ff, #f0
    db #41, #ff, #ff, #ff, #ff, #f0
    db #63, #ff, #ff, #ff, #ff, #f8
    db #7f, #ff, #ff, #ff, #ff, #ff
    db #bf, #ff, #ff, #ff, #ff, #ff
    db #aa, #ba, #aa, #af, #ba, #a8
    db #27, #47, #7e, #aa, #aa, #aa
    db #55, #55, #75, #55, #55, #55  ; mdl-asm+:html:gfx(bitmap,pre,6,14,2)

L7725_ui_key_sprite:
    db 1, 14, #fc  ; width, height, and-mask
    dw 14  ; frame size
    db #fc, #80, #b8, #08, #08, #f8, #80, #ec, #ec, #ec, #ec, #74, #34, #74  ; mdl-asm+:html:gfx(bitmap,pre,1,14,2)

L7738_ui_spirit_meter_bg_sprite:
    db 8, 8, #ff  ; width, height, and-mask
    dw 72  ; frame size
           ; Note: this value is wrong, it should be 64, but it does not matter, as there is only one frame in this sprite.
    db #ff, #ff, #ff, #ff, #ff, #ff, #ff, #ff
    db #ff, #ff, #ff, #ff, #ff, #ff, #ff, #ff
    db #ff, #ff, #ff, #ff, #ff, #ff, #ff, #ff
    db #fb, #ff, #ff, #ff, #ff, #ff, #fd, #ff
    db #ff, #ff, #ff, #ff, #ff, #ff, #df, #ff
    db #ff, #ef, #ff, #bf, #ef, #ff, #ff, #bb
    db #ff, #7f, #f7, #ff, #ff, #fe, #ff, #ff
    db #ff, #ff, #ff, #ff, #ff, #ff, #ff, #ff  ; mdl-asm+:html:gfx(bitmap,pre,8,8,2)

L777d_ui_spirit_meter_indicator_sprite:
    db 2, 8, #fc  ; width, height, and-mask
    dw 16  ; frame size
    db #f0, #3f, #c0, #0f, #82, #87, #01, #43
    db #00, #03, #80, #07, #c0, #0f, #f0, #3f  ; mdl-asm+:html:gfx(bitmap,pre,2,8,2)

L7792_ui_compass_eye_sprites:
    db 2, 5, #ff
    dw 10
    db #00, #fc, #43, #df, #73, #87, #43, #cf, #00, #fc  ; mdl-asm+:html:gfx(bitmap,pre,2,5,2)
    db #00, #dc, #43, #87, #73, #cf, #43, #ff, #00, #fc  ; mdl-asm+:html:gfx(bitmap,pre,2,5,2)
    db #00, #fc, #43, #ff, #73, #df, #43, #87, #00, #cc  ; mdl-asm+:html:gfx(bitmap,pre,2,5,2)
    db #00, #fc, #43, #7f, #72, #1f, #43, #3f, #01, #fc  ; mdl-asm+:html:gfx(bitmap,pre,2,5,2)
    db #00, #fc, #43, #f7, #73, #e1, #43, #f3, #00, #fc  ; mdl-asm+:html:gfx(bitmap,pre,2,5,2)
    db #00, #00, #40, #d8, #73, #87, #43, #cf, #00, #fc  ; mdl-asm+:html:gfx(bitmap,pre,2,5,2)
    db #00, #00, #40, #00, #71, #8c, #43, #cf, #00, #fc  ; mdl-asm+:html:gfx(bitmap,pre,2,5,2)
    db #00, #00, #40, #00, #70, #00, #43, #ce, #00, #fc  ; mdl-asm+:html:gfx(bitmap,pre,2,5,2)
    db #00, #00, #40, #00, #70, #00, #40, #00, #00, #00  ; mdl-asm+:html:gfx(bitmap,pre,2,5,2)
    db #00, #fc, #43, #cf, #73, #87, #43, #cf, #00, #fc  ; mdl-asm+:html:gfx(bitmap,pre,2,5,2)
    db #00, #fc, #43, #ff, #73, #cf, #43, #cf, #00, #fc  ; mdl-asm+:html:gfx(bitmap,pre,2,5,2)

L7805_ui_strength_bg_sprite:
    db 9, 15, #ff  ; width, height, and-mask
    dw 135  ; frame size
    db #00, #00, #00, #00, #00, #00, #00, #00, #00
    db #00, #00, #00, #00, #00, #00, #00, #00, #00
    db #00, #00, #00, #00, #00, #00, #00, #00, #00
    db #00, #00, #00, #00, #00, #00, #00, #00, #00
    db #00, #00, #00, #00, #00, #00, #00, #00, #00
    db #00, #00, #00, #00, #00, #00, #00, #00, #00
    db #00, #00, #00, #00, #00, #00, #00, #00, #00
    db #00, #00, #00, #00, #00, #00, #00, #00, #00
    db #00, #00, #00, #00, #00, #00, #00, #00, #00
    db #00, #00, #00, #00, #00, #00, #00, #00, #00
    db #00, #00, #00, #00, #00, #00, #00, #00, #00
    db #00, #00, #15, #55, #55, #55, #50, #00, #00
    db #0a, #aa, #aa, #aa, #aa, #aa, #aa, #aa, #a0
    db #1f, #ff, #ff, #ff, #ff, #ff, #ff, #ff, #f8
    db #3f, #ff, #ff, #ff, #ff, #ff, #ff, #ff, #fc  ; mdl-asm+:html:gfx(bitmap,pre,9,15,2)

L7891_ui_strength_bar_sprite:
    db 9, 3, #ff
    dw 27
    db #1f, #ff, #ff, #ff, #ff, #ff, #ff, #ff, #f8
    db #1f, #ff, #ff, #ff, #ff, #ff, #ff, #ff, #f8
    db #0a, #aa, #aa, #aa, #aa, #aa, #aa, #aa, #a8  ; mdl-asm+:html:gfx(bitmap,pre,9,3,2)

L78b1_ui_strength_weight_sprite:
    db #01, #0f, #f0
    dw #000f
    db #60, #60, #60, #60, #60, #60, #60, #60, #60, #60, #60, #60, #60, #40, #20  ; mdl-asm+:html:gfx(bitmap,pre,1,15,2)
    db #00, #60, #60, #60, #60, #60, #60, #60, #60, #60, #60, #60, #40, #20, #f0  ; mdl-asm+:html:gfx(bitmap,pre,1,15,2)
    db #00, #00, #60, #60, #60, #60, #60, #60, #60, #60, #60, #40, #20, #f0, #f0  ; mdl-asm+:html:gfx(bitmap,pre,1,15,2)
    db #00, #00, #00, #60, #60, #60, #60, #60, #60, #60, #40, #20, #f0, #f0, #f0  ; mdl-asm+:html:gfx(bitmap,pre,1,15,2)

L78f2_background_mountains_gfx:
    db #06, #00, #00, #10, #00, #00, #00, #00, #00, #00, #0c, #00, #00, #00, #00, #00
    db #0b, #00, #00, #38, #01, #a0, #00, #00, #00, #00, #1e, #30, #00, #00, #00, #00
    db #17, #80, #00, #7c, #03, #d0, #00, #00, #01, #00, #3f, #5c, #80, #00, #18, #00
    db #23, #c0, #00, #fe, #0d, #fe, #06, #00, #02, #80, #7e, #be, #c0, #00, #3c, #00
    db #47, #e0, #01, #57, #56, #ff, #0f, #80, #05, #40, #f5, #fb, #40, #00, #76, #00
    db #93, #d0, #0a, #ab, #ab, #ff, #af, #c3, #2a, #a1, #eb, #fe, #a8, #00, #de, #00
    db #21, #a8, #75, #55, #41, #ff, #d6, #ef, #d5, #53, #57, #fc, #14, #01, #b7, #07
    db #42, #d5, #ea, #aa, #92, #fb, #eb, #ab, #ea, #aa, #ae, #fa, #4a, #82, #ea, #be
    db #97, #ab, #d5, #55, #25, #dd, #75, #45, #f5, #55, #7d, #dd, #25, #55, #d5, #54
    db #2f, #f7, #aa, #aa, #53, #ea, #a8, #13, #fa, #aa, #ea, #be, #42, #ab, #aa, #a9
    db #5f, #dd, #d5, #55, #07, #55, #02, #45, #fd, #51, #55, #57, #15, #57, #d5, #52
    db #af, #ee, #fa, #aa, #2b, #aa, #80, #8b, #fe, #aa, #aa, #ae, #aa, #be, #aa, #a4
    db #5a, #b5, #5d, #5c, #56, #d5, #29, #1f, #ff, #55, #55, #5b, #55, #7d, #55, #09
    db #b5, #5a, #af, #ba, #ad, #aa, #92, #3e, #bf, #ea, #aa, #af, #ab, #ea, #aa, #02
    db #5a, #f5, #55, #fd, #57, #55, #05, #5f, #57, #fd, #55, #55, #57, #55, #50, #15
    db #af, #ba, #aa, #fe, #ae, #fa, #aa, #be, #aa, #bf, #aa, #aa, #aa, #aa, #82, #aa
    db #55, #55, #55, #5f, #d5, #fd, #55, #55, #55, #5f, #fd, #55, #55, #55, #55, #55
    db #ea, #aa, #aa, #aa, #aa, #aa, #aa, #aa, #aa, #aa, #ff, #ff, #ff, #ff, #ff, #ff  ; mdl-asm+:html:gfx(bitmap,pre,16,18,2)

L7a12_waving_flag_gfx_properties:
    db 3, 9, #ff  ; width (in bytes), height, and-mask of last byte
    dw 27  ; 3 * 9 (bytes of each frame)
    ; Waving flag frame 1:
    db #00, #03, #f6
    db #00, #07, #fe
    db #07, #ff, #f6
    db #01, #ff, #f6
    db #00, #7f, #f6
    db #00, #1f, #f6
    db #01, #ff, #f6
    db #03, #ff, #7e
    db #03, #9f, #06  ; mdl-asm+:html:gfx(bitmap,pre,3,9,2)
    ; Waving flag frame 2:
    db #00, #1f, #06
    db #00, #3f, #fe
    db #0f, #ff, #f6
    db #01, #ff, #f6
    db #00, #7f, #f6
    db #00, #3f, #f6
    db #01, #ff, #f6
    db #03, #f9, #fe
    db #0f, #f0, #06  ; mdl-asm+:html:gfx(bitmap,pre,3,9,2)
    ; Waving flag frame 3:
    db #00, #7e, #06
    db #01, #ff, #1e
    db #07, #ff, #f6
    db #00, #ff, #f6
    db #00, #3f, #f6
    db #01, #ff, #f6
    db #07, #ff, #f6
    db #0f, #87, #fe
    db #00, #01, #e6  ; mdl-asm+:html:gfx(bitmap,pre,3,9,2)
    ; Waving flag frame 4:    
    db #00, #00, #7e
    db #01, #fd, #f6
    db #07, #ff, #f6
    db #00, #7f, #f6
    db #00, #1f, #f6
    db #00, #3f, #f6
    db #00, #ff, #f6
    db #07, #ff, #fe
    db #0f, #1f, #06  ; mdl-asm+:html:gfx(bitmap,pre,3,9,2)

; --------------------------------
; Unused graphics?
L7a83:
    db #0f, #ff, #f0 
    db #08, #00, #10
    db #09, #ff, #90
    db #09, #00, #90  ; mdl-asm+:html:gfx(bitmap,pre,3,4,2)

L7a8f:
    db #01, #07, #ff, #07, #00  ; mdl-asm+:html:gfx(bitmap,pre,1,5,2)
L7a94:
    db #7e, #c3, #81, #81, #81, #c3, #7e  ; mdl-asm+:html:gfx(bitmap,pre,1,7,2)

; --------------------------------
L7a9b_lightning_gfx:
    db #00, #40, #00, #40
    db #00, #40, #00, #40
    db #00, #40, #00, #40
    db #00, #40, #00, #80
    db #01, #80, #01, #00
    db #01, #00, #02, #00
    db #04, #00, #08, #00
    db #18, #00, #10, #00
    db #30, #00, #20, #00
    db #20, #00, #20, #00
    db #70, #00, #50, #00
    db #50, #00, #88, #00
    db #08, #00, #04, #00
    db #02, #00, #02, #00
    db #01, #00, #01, #00
    db #01, #00, #00, #80
    db #00, #c0, #00, #40
    db #00, #20, #00, #10
    db #00, #08, #00, #0c
    db #00, #1c, #00, #32
    db #00, #22, #00, #c2
    db #01, #81, #02, #01
    db #02, #00, #02, #00
    db #02, #00, #02, #00
    db #02, #00, #02, #00
    db #06, #00, #04, #00
    db #04, #00, #0c, #00
    db #18, #00, #30, #00
    db #20, #00, #20, #00
    db #70, #00, #4c, #00
    db #86, #00, #02, #00
    db #01, #00, #01, #00
    db #00, #80, #00, #80
    db #00, #80, #00, #80
    db #00, #80, #00, #80
    db #00, #80, #00, #60
    db #00, #30, #00, #08
    db #00, #08, #00, #06
    db #00, #02, #00, #02
    db #00, #02, #00, #02
    db #00, #02, #00, #02
    db #00, #03, #00, #01
    db #00, #01, #00, #00  ; mdl-asm+:html:gfx(bitmap,pre,2,86,2)


; --------------------------------
; Each block of 8 bytes correspods to a character. So, this includes
; a definition of the font being used, the first character is ' ':
; these tags inside comments are used to visualize the gfx using MDL with the "-mdl-asm+:html" flag.
L7b47_font:
    db #00, #00, #00, #00, #00, #00, #00, #00  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #1c, #1c, #1c, #18, #18, #00, #18, #18  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #66, #66, #44, #22, #00, #00, #00, #00  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #00, #7f, #7f, #7f, #7f, #7f, #7f, #00  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #10, #54, #38, #fe, #38, #54, #10, #00  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #3c, #42, #9d, #b1, #b1, #9d, #42, #3c  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #78, #cc, #cc, #78, #db, #cf, #ce, #7b  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #30, #30, #10, #20, #00, #00, #00, #00  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #10, #20, #40, #40, #40, #40, #20, #10  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #10, #08, #04, #04, #04, #04, #08, #10  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #10, #54, #38, #fe, #38, #54, #10, #00  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #00, #00, #10, #10, #7c, #10, #10, #00  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #00, #00, #00, #00, #18, #18, #08, #10  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #00, #00, #00, #00, #3c, #00, #00, #00  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #00, #00, #00, #00, #00, #00, #18, #18  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #01, #02, #04, #08, #10, #20, #40, #80  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #18, #66, #c3, #c3, #c3, #c3, #66, #18  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #18, #38, #18, #18, #18, #18, #18, #18  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #9e, #61, #01, #7e, #e0, #c6, #e3, #fe  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #ee, #73, #03, #3e, #03, #01, #7f, #e6  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #0e, #1c, #38, #71, #fd, #e6, #0c, #0c  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #fd, #86, #80, #7e, #07, #63, #c7, #7c  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #3d, #66, #c0, #f0, #fc, #c6, #66, #3c  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #b3, #4e, #06, #0c, #0c, #18, #18, #3c  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #7c, #c6, #c6, #7c, #c6, #c2, #fe, #4c  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #3c, #4e, #c6, #c6, #4e, #36, #46, #3c  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #00, #18, #18, #00, #00, #18, #18, #00  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #00, #18, #18, #00, #00, #18, #08, #10  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #03, #0c, #30, #c0, #30, #0c, #03, #00  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #00, #00, #ff, #00, #ff, #00, #00, #00  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #c0, #30, #0c, #03, #0c, #30, #c0, #00  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #7c, #c6, #06, #0c, #30, #30, #00, #30  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #00, #08, #0c, #fe, #ff, #fe, #0c, #08  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #1e, #1c, #1e, #66, #be, #26, #43, #e3  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #ee, #73, #23, #3e, #23, #21, #7f, #e6  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #39, #6e, #c6, #c0, #c0, #c2, #63, #3e  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #ec, #72, #23, #23, #23, #23, #72, #ec  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #ce, #7f, #61, #6c, #78, #61, #7f, #ce  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #ce, #7f, #61, #6c, #78, #60, #60, #f0  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #3d, #66, #c0, #c1, #ce, #c6, #66, #3c  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #e7, #66, #66, #6e, #76, #66, #66, #e7  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #66, #3c, #18, #18, #18, #18, #3c, #66  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #33, #1e, #0c, #8c, #4c, #cc, #dc, #78  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #f2, #67, #64, #68, #7e, #66, #66, #f3  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #d8, #70, #60, #60, #66, #61, #f3, #7e  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #c3, #66, #6e, #76, #56, #46, #46, #ef  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #87, #62, #72, #7a, #5e, #4e, #46, #e1  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #18, #66, #c3, #c3, #c3, #c3, #66, #18  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #ec, #72, #63, #63, #72, #6c, #60, #f0  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #3c, #66, #c3, #c3, #66, #3c, #31, #1e  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #ec, #72, #63, #63, #76, #6c, #66, #f1  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #79, #86, #80, #7e, #07, #63, #c7, #7c  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #01, #7f, #fe, #98, #58, #18, #18, #3c  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #f7, #62, #62, #62, #62, #62, #f2, #3c  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #f3, #61, #72, #72, #32, #32, #1c, #3e  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #c3, #62, #62, #6a, #6e, #76, #66, #c3  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #f3, #72, #3c, #38, #1c, #3c, #4e, #cf  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #e3, #72, #34, #38, #18, #18, #18, #3c  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)
    db #7f, #87, #0e, #1c, #38, #71, #fd, #e6  ; mdl-asm+:html:gfx(bitmap,pre,1,8,2)


; --------------------------------
L7d1f_text_save_load_quit:
    db 0, "S-SAVE L-LOAD Q-QUIT"
L7d34_text_keys:
    db 0, "KEYS"
L7d39_text_spirits:
    db 0, "SPIRITS"
L7d41_text_strength:
    db 0, "STRENGTH"
L7d4a_text_collected:
    db 0, " XX COLLECTED  "
L7d5a_text_destroyed:
    db 0, " XX DESTROYED  "
L7d6a_text_score:
    db 1, "SCORE  XXXXXXX "
L7d7a_text_filename:
    db 0, "FILENAME :   "

L7d88_action_pointer_viewport_sprite:
    db 0, 0, 2, 9
    dw L7e3e  ; empty buffer
    dw L7dae, L7dc0, L7dd2, L7de4  ; pointer mask
    dw L7df6, L7e08, L7e1a, L7e2c
    dw L7e50, L7e62, L7e74, L7e86  ; action/throw pointer
    dw L7e98, L7eaa, L7ebc, L7ece
L7dae:
    db #e3, #ff, #e3, #ff, #e3, #ff
    db #1c, #7f, #1c, #7f, #1c, #7f
    db #e3, #ff, #e3, #ff, #e3, #ff  ; mdl-asm+:html:gfx(bitmap,pre,2,9,2) 
L7dc0:
    db #f1, #ff, #f1, #ff, #f1, #ff
    db #8e, #3f, #8e, #3f, #8e, #3f
    db #f1, #ff, #f1, #ff, #f1, #ff  ; mdl-asm+:html:gfx(bitmap,pre,2,9,2) 
L7dd2:
    db #f8, #ff, #f8, #ff, #f8, #ff
    db #c7, #1f, #c7, #1f, #c7, #1f
    db #f8, #ff, #f8, #ff, #f8, #ff  ; mdl-asm+:html:gfx(bitmap,pre,2,9,2) 
L7de4:
    db #fc, #7f, #fc, #7f, #fc, #7f
    db #e3, #8f, #e3, #8f, #e3, #8f
    db #fc, #7f, #fc, #7f, #fc, #7f  ; mdl-asm+:html:gfx(bitmap,pre,2,9,2) 
L7df6:
    db #fe, #3f, #fe, #3f, #fe, #3f
    db #f1, #c7, #f1, #c7, #f1, #c7
    db #fe, #3f, #fe, #3f, #fe, #3f  ; mdl-asm+:html:gfx(bitmap,pre,2,9,2) 
L7e08:
    db #ff, #1f, #ff, #1f, #ff, #1f
    db #f8, #e3, #f8, #e3, #f8, #e3
    db #ff, #1f, #ff, #1f, #ff, #1f  ; mdl-asm+:html:gfx(bitmap,pre,2,9,2) 
L7e1a:
    db #ff, #8f, #ff, #8f, #ff, #8f
    db #fc, #71, #fc, #71, #fc, #71
    db #ff, #8f, #ff, #8f, #ff, #8f  ; mdl-asm+:html:gfx(bitmap,pre,2,9,2) 
L7e2c:
    db #ff, #c7, #ff, #c7, #ff, #c7
    db #fe, #38, #fe, #38, #fe, #38
    db #ff, #c7, #ff, #c7, #ff, #c7  ; mdl-asm+:html:gfx(bitmap,pre,2,9,2) 
L7e3e:
    db #00, #00, #00, #00, #00, #00
    db #00, #00, #00, #00, #00, #00
    db #00, #00, #00, #00, #00, #00  ; mdl-asm+:html:gfx(bitmap,pre,2,9,2) 
L7e50:
    db #14, #00, #14, #00, #14, #00
    db #00, #00, #e3, #80, #00, #00
    db #14, #00, #14, #00, #14, #00  ; mdl-asm+:html:gfx(bitmap,pre,2,9,2) 
L7e62:
    db #0a, #00, #0a, #00, #0a, #00
    db #00, #00, #71, #c0, #00, #00
    db #0a, #00, #0a, #00, #0a, #00  ; mdl-asm+:html:gfx(bitmap,pre,2,9,2) 
L7e74:
    db #05, #00, #05, #00, #05, #00
    db #00, #00, #38, #e0, #00, #00
    db #05, #00, #05, #00, #05, #00  ; mdl-asm+:html:gfx(bitmap,pre,2,9,2) 
L7e86:
    db #02, #80, #02, #80, #02, #80
    db #00, #00, #1c, #70, #00, #00
    db #02, #80, #02, #80, #02, #80  ; mdl-asm+:html:gfx(bitmap,pre,2,9,2) 
L7e98:
    db #01, #40, #01, #40, #01, #40
    db #00, #00, #0e, #38, #00, #00
    db #01, #40, #01, #40, #01, #40  ; mdl-asm+:html:gfx(bitmap,pre,2,9,2) 
L7eaa:
    db #00, #a0, #00, #a0, #00, #a0
    db #00, #00, #07, #1c, #00, #00
    db #00, #a0, #00, #a0, #00, #a0  ; mdl-asm+:html:gfx(bitmap,pre,2,9,2) 
L7ebc:
    db #00, #50, #00, #50, #00, #50
    db #00, #00, #03, #8e, #00, #00
    db #00, #50, #00, #50, #00, #50  ; mdl-asm+:html:gfx(bitmap,pre,2,9,2) 
L7ece:
    db #00, #28, #00, #28, #00, #28
    db #00, #00, #01, #c7, #00, #00
    db #00, #28, #00, #28, #00, #28  ; mdl-asm+:html:gfx(bitmap,pre,2,9,2) 


L7ee0_stone_viewport_sprite_size1:
    db 0, 0, 2, 4
    dw L7f16  ; empty buffer
    dw L7f06, L7f06, L7f06, L7f06
    dw L7f06, L7f06, L7f06, L7f06
    dw L7f0e, L7f0e, L7f0e, L7f0e
    dw L7f0e, L7f0e, L7f0e, L7f0e
L7f06:
    db #00, #3f, #00, #3f, #80, #7f, #c0, #ff  ; mdl-asm+:html:gfx(bitmap,pre,2,4,2) 
L7f0e:
    db #ff, #80, #ff, #80, #7f, #00, #3e, #00  ; mdl-asm+:html:gfx(bitmap,pre,2,4,2) 
L7f16:
    db #00, #00, #00, #00, #00, #00, #00, #00  ; mdl-asm+:html:gfx(bitmap,pre,2,4,2) 


L7f1e_stone_viewport_sprite_size2:
    db 0, 0, 2, 5
    dw L7fe4  ; empty buffer
    dw L7f44, L7f4e, L7f58, L7f62
    dw L7f6c, L7f76, L7f80, L7f8a
    dw L7f94, L7f9e, L7fa8, L7fb2
    dw L7fbc, L7fc6, L7fd0, L7fda
L7f44:
    db #c1, #ff, #80, #ff, #00, #7f, #80, #ff, #c1, #ff  ; mdl-asm+:html:gfx(bitmap,pre,2,5,2) 
L7f4e:
    db #e0, #ff, #c0, #7f, #80, #3f, #c0, #7f, #e0, #ff  ; mdl-asm+:html:gfx(bitmap,pre,2,5,2) 
L7f58:
    db #f0, #7f, #e0, #3f, #c0, #1f, #e0, #3f, #f0, #7f  ; mdl-asm+:html:gfx(bitmap,pre,2,5,2) 
L7f62:
    db #f8, #3f, #f0, #1f, #e0, #0f, #f0, #1f, #f8, #3f  ; mdl-asm+:html:gfx(bitmap,pre,2,5,2) 
L7f6c:
    db #fc, #1f, #f8, #0f, #f0, #07, #f8, #0f, #fc, #1f  ; mdl-asm+:html:gfx(bitmap,pre,2,5,2) 
L7f76:
    db #fe, #0f, #fc, #07, #f8, #03, #fc, #07, #fe, #0f  ; mdl-asm+:html:gfx(bitmap,pre,2,5,2) 
L7f80:
    db #ff, #07, #fe, #03, #fc, #01, #fe, #03, #ff, #07  ; mdl-asm+:html:gfx(bitmap,pre,2,5,2) 
L7f8a:
    db #ff, #83, #ff, #01, #fe, #00, #ff, #01, #ff, #83  ; mdl-asm+:html:gfx(bitmap,pre,2,5,2) 
L7f94:
    db #3c, #00, #7e, #00, #ff, #00, #7e, #00, #3c, #00  ; mdl-asm+:html:gfx(bitmap,pre,2,5,2) 
L7f9e:
    db #1e, #00, #3f, #00, #7f, #80, #3f, #00, #1e, #00  ; mdl-asm+:html:gfx(bitmap,pre,2,5,2) 
L7fa8:
    db #0f, #00, #1f, #80, #3f, #c0, #1f, #80, #0f, #00  ; mdl-asm+:html:gfx(bitmap,pre,2,5,2) 
L7fb2:
    db #07, #80, #0f, #c0, #1f, #e0, #0f, #c0, #07, #80  ; mdl-asm+:html:gfx(bitmap,pre,2,5,2) 
L7fbc:
    db #03, #c0, #07, #e0, #0f, #f0, #07, #e0, #03, #c0  ; mdl-asm+:html:gfx(bitmap,pre,2,5,2) 
L7fc6:
    db #01, #e0, #03, #f0, #07, #f8, #03, #f0, #01, #e0  ; mdl-asm+:html:gfx(bitmap,pre,2,5,2) 
L7fd0:
    db #00, #f0, #01, #f8, #03, #fc, #01, #f8, #00, #f0  ; mdl-asm+:html:gfx(bitmap,pre,2,5,2) 
L7fda:
    db #00, #78, #00, #fc, #01, #fe, #00, #fc, #00, #78  ; mdl-asm+:html:gfx(bitmap,pre,2,5,2) 
L7fe4:
    db #00, #00, #00, #00, #00, #00, #00, #00, #00, #00  ; mdl-asm+:html:gfx(bitmap,pre,2,5,2) 

L7fee_stone_viewport_sprite_size3:
    db 0, 0, 2, 4
    dw L8094  ; empty buffer
    dw L8014, L801c, L8024, L802c
    dw L8034, L803c, L8044, L804c
    dw L8054, L805c, L8064, L806c
    dw L8074, L807c, L8084, L808c
L8014:
    db #87, #ff, #03, #ff, #03, #ff, #87, #ff  ; mdl-asm+:html:gfx(bitmap,pre,2,4,2) 
L801c:
    db #c3, #ff, #81, #ff, #81, #ff, #c3, #ff  ; mdl-asm+:html:gfx(bitmap,pre,2,4,2) 
L8024:
    db #e1, #ff, #c0, #ff, #c0, #ff, #e1, #ff  ; mdl-asm+:html:gfx(bitmap,pre,2,4,2) 
L802c:
    db #f0, #ff, #e0, #7f, #e0, #7f, #f0, #ff  ; mdl-asm+:html:gfx(bitmap,pre,2,4,2) 
L8034:
    db #f8, #7f, #f0, #3f, #f0, #3f, #f8, #7f  ; mdl-asm+:html:gfx(bitmap,pre,2,4,2) 
L803c:
    db #fc, #3f, #f8, #1f, #f8, #1f, #fc, #3f  ; mdl-asm+:html:gfx(bitmap,pre,2,4,2) 
L8044:
    db #fe, #1f, #fc, #0f, #fc, #0f, #fe, #1f  ; mdl-asm+:html:gfx(bitmap,pre,2,4,2) 
L804c:
    db #ff, #0f, #fe, #07, #fe, #07, #ff, #0f  ; mdl-asm+:html:gfx(bitmap,pre,2,4,2) 
L8054:
    db #70, #00, #f8, #00, #f8, #00, #70, #00  ; mdl-asm+:html:gfx(bitmap,pre,2,4,2) 
L805c:
    db #38, #00, #7c, #00, #7c, #00, #38, #00  ; mdl-asm+:html:gfx(bitmap,pre,2,4,2) 
L8064:
    db #1c, #00, #3e, #00, #3e, #00, #1c, #00  ; mdl-asm+:html:gfx(bitmap,pre,2,4,2) 
L806c:
    db #0e, #00, #1f, #00, #1f, #00, #0e, #00  ; mdl-asm+:html:gfx(bitmap,pre,2,4,2) 
L8074:
    db #07, #00, #0f, #80, #0f, #80, #07, #00  ; mdl-asm+:html:gfx(bitmap,pre,2,4,2) 
L807c:
    db #03, #80, #07, #c0, #07, #c0, #03, #80  ; mdl-asm+:html:gfx(bitmap,pre,2,4,2) 
L8084:
    db #01, #c0, #03, #e0, #03, #e0, #01, #c0  ; mdl-asm+:html:gfx(bitmap,pre,2,4,2) 
L808c:
    db #00, #e0, #01, #f0, #01, #f0, #00, #e0  ; mdl-asm+:html:gfx(bitmap,pre,2,4,2) 
L8094:
    db #00, #00, #00, #00, #00, #00, #00, #00  ; mdl-asm+:html:gfx(bitmap,pre,2,4,2) 

L909c_stone_viewport_sprite_size4:
    db 0, 0, 2, 3
    dw L8122  ; empty buffer
    dw L80c2, L80c8, L80ce, L80d4
    dw L80da, L80e0, L80e6, L80ec
    dw L80f2, L80f8, L80fe, L8104
    dw L810a, L8110, L8116, L811c
L80c2:
    db #8f, #ff, #07, #ff, #8f, #ff  ; mdl-asm+:html:gfx(bitmap,pre,2,3,2) 
L80c8:
    db #c7, #ff, #83, #ff, #c7, #ff  ; mdl-asm+:html:gfx(bitmap,pre,2,3,2) 
L80ce:
    db #e3, #ff, #c1, #ff, #e3, #ff  ; mdl-asm+:html:gfx(bitmap,pre,2,3,2) 
L80d4:
    db #f1, #ff, #e0, #ff, #f1, #ff  ; mdl-asm+:html:gfx(bitmap,pre,2,3,2) 
L80da:
    db #f8, #ff, #f0, #7f, #f8, #ff  ; mdl-asm+:html:gfx(bitmap,pre,2,3,2) 
L80e0:
    db #fc, #7f, #f8, #3f, #fc, #7f  ; mdl-asm+:html:gfx(bitmap,pre,2,3,2) 
L80e6:
    db #fe, #3f, #fc, #1f, #fe, #3f  ; mdl-asm+:html:gfx(bitmap,pre,2,3,2) 
L80ec:
    db #ff, #1f, #fe, #0f, #ff, #1f  ; mdl-asm+:html:gfx(bitmap,pre,2,3,2) 
L80f2:
    db #60, #00, #f0, #00, #60, #00  ; mdl-asm+:html:gfx(bitmap,pre,2,3,2) 
L80f8:
    db #30, #00, #78, #00, #30, #00  ; mdl-asm+:html:gfx(bitmap,pre,2,3,2) 
L80fe:
    db #18, #00, #3c, #00, #18, #00  ; mdl-asm+:html:gfx(bitmap,pre,2,3,2) 
L8104:
    db #0c, #00, #1e, #00, #0c, #00  ; mdl-asm+:html:gfx(bitmap,pre,2,3,2) 
L810a:
    db #06, #00, #0f, #00, #06, #00  ; mdl-asm+:html:gfx(bitmap,pre,2,3,2) 
L8110:
    db #03, #00, #07, #80, #03, #00  ; mdl-asm+:html:gfx(bitmap,pre,2,3,2) 
L8116:
    db #01, #80, #03, #c0, #01, #80  ; mdl-asm+:html:gfx(bitmap,pre,2,3,2) 
L811c:
    db #00, #c0, #01, #e0, #00, #c0  ; mdl-asm+:html:gfx(bitmap,pre,2,3,2) 
L8122:
    db #00, #00, #00, #00, #00, #00  ; mdl-asm+:html:gfx(bitmap,pre,2,3,2) 


; --------------------------------
; Temporary data for function 'L8132_load_or_save_to_tape'
L8128_initial_pressed_key:
    db #c0
L8129_filename_length:
    db #01
L812a_filename_ptr:
    dw #0080
l812c_savegame_data_size:
    dw #01c0
L812e_savegame_data_end_ptr:
    dw #00e0
L8130_checksum:
    dw #00c0


; --------------------------------
; Asks the player to type a savegame name, and load/ssaves a game.
L8132_load_or_save_to_tape:
    ld (L8128_initial_pressed_key), a  ; Remember whether we had pressed 'S' or 'L'.
    call Lc3f4_read_filename
    ld (L8129_filename_length), a
    ld (L812a_filename_ptr), hl
    ld a, (L8128_initial_pressed_key)  ; Restore which key was pressed to get to this menu.
    cp 'S'  ; Check if we wanted to save or load:
    jp nz, L8219_load

    ; Save game:
    ; Copy the game data to save to the buffer:
    ld de, L5cbc_render_buffer
    ld hl, L6aad_player_current_x
    ld bc, L6b24_savegame_data_end - L6aad_savegame_data_start
    ldir

    ; Add area object states:
    ld a, (Ld082_n_areas)
    ld c, a
    ld iy, Ld0d1_area_offsets
    ex de, hl  ; hl = ptr to the next position in the save game data
L815a_save_game_area_loop:
    ld e, (iy)
    ld d, (iy + 1)  ; Get area pointer offset
    inc iy
    inc iy
    ld ix, Ld082_area_reference_start
    add ix, de
    ld b, (ix + AREA_N_OBJECTS)
    ld de, 8
    add ix, de  ; skip the header
L8172_save_game_next_object_loop:
    ld a, (ix + OBJECT_TYPE_AND_FLAGS)  ; save the object state
    ld (hl), a
    inc hl
    ld e, (ix + OBJECT_SIZE)
    add ix, de  ; next object
    djnz L8172_save_game_next_object_loop
    dec c
    jr nz, L815a_save_game_area_loop

    ld (L812e_savegame_data_end_ptr), hl
    ld de, L5cbc_render_buffer
    or a
    sbc hl, de
    ld (l812c_savegame_data_size), hl
    call L838c_checksum
    ld (L8130_checksum), bc

    ld de, (L812e_savegame_data_end_ptr)

    ; Generate the savegame header (19 bytes):
    ; - 1 byte: 30
    ; - 12 bytes: filename
    ; - 2 bytes: savegame size
    ; - 2 bytes: (Ld083_game_version)
    ; - 2 bytes: checksum
    ld a, 30  ; Header start
    ld (de), a
    inc de
    ld hl, (L812a_filename_ptr)
    ld bc, 12
    ldir  ; Append the filename to the savegame data.

    ; Append the savegame datasize to the savegame header:
    ld hl, (l812c_savegame_data_size)
    ex de, hl
    ld (hl), e
    inc hl
    ld (hl), d
    inc hl

    ; Append the 2 bytes at (Ld083_game_version) to the savegame header:
    ld de, (Ld083_game_version)
    ld (hl), e
    inc hl
    ld (hl), d
    inc hl

    ; Append the checksum to the header:
    ld de, (L8130_checksum)
    ld (hl), e
    inc hl
    ld (hl), d

    ld ix, L725c_videomem_row_pointers + 68 * 2
    ld hl, L7547_text_play_record
    ld de, #0d27
    call Ld01c_draw_string
    ld ix, L725c_videomem_row_pointers + 79 * 2
    ld hl, L7583_text_then_any_key
    call Ld01c_draw_string

    ; Wait until a key is pressed & released:
L81d2_key_press_wait_loop:
    call Lbfd4_read_keyboard_and_joystick_input
    jr c, L81d2_key_press_wait_loop
L81d7_key_release_wait_loop:
    call Lbfd4_read_keyboard_and_joystick_input
    jr nc, L81d7_key_release_wait_loop

    ld hl, L7538_text_spaces
    call Ld01c_draw_string
    ld ix, L725c_videomem_row_pointers + 68 * 2
    ld hl, L7592_text_saving_file
    call Ld01c_draw_string
    ld iy, (L747d)
    ld ix, (L812e_savegame_data_end_ptr)  ; address to save
    ld de, 19  ; Size of the header
    xor a
    ; Save the header:
    call L04c6_BIOS_CASSETTE_SAVE_NO_BREAK_TEST
    jp nc, L8362_done_loading_saving_with_pause
    ei
    ; Wait 50 interrupts:
    ld a, 50
    ld (L74a5_interrupt_timer), a
L8204_pause_loop:
    ld a, (L74a5_interrupt_timer)
    or a
    jr nz, L8204_pause_loop
    ld ix, L5cbc_render_buffer  ; address to save
    ld de, (l812c_savegame_data_size)  ; amount of bytes to save
    dec a
    ; Save the savegame:
    call L04c6_BIOS_CASSETTE_SAVE_NO_BREAK_TEST
    jp L8362_done_loading_saving_with_pause

L8219_load:
    ; Load game:
    ld iy, (L747d)
    ld ix, L725c_videomem_row_pointers + 68 * 2
    ld hl, L75b0_text_searching
    ld de, #0e27
    call Ld01c_draw_string
L822a:
    ld ix, L5cbc_render_buffer  ; address to load to
    ld de, 19 - 1  ; Amount of bytes to load (19)
    ; Set the flags/values the BIOS routine expects to load:
    xor a
    scf
    inc e
    ex af, af'  ; since we are skipping tests, we need to pre "ex" af, since the function would do this during the tests.
    di
    call L0562_BIOS_READ_FROM_TAPE_SKIP_TESTS
    push af
        ld a, #7f
        in a, (ULA_PORT)
        rra
        jp nc, L831d_done_loading_saving_pop  ; If space (break?) was pressed, cancel.
    pop af
    jr nc, L822a  ; If load failed, retry.
    ld ix, L5cbc_render_buffer

    ; Check header is correct:
    ; - 1 byte: 30
    ; - 12 bytes: filename
    ; - 2 bytes: savegame size
    ; - 2 bytes: (Ld083_game_version)
    ; - 2 bytes: checksum
    ld a, 30
    cp (ix)
    jr nz, L822a  ; If the first byte is not the header start byte, retry.
    ld ix, L725c_videomem_row_pointers + 68 * 2
    ld hl, L75a1_text_found
    ld de, #0e27
    call Ld01c_draw_string

    ld ix, L5cbc_render_buffer + 1
    ld e, (ix + 12)
    ld d, (ix + 13)  ; de = savegame size
    ld (ix + 12), ' '  ; replace savegame size by spaces, to print to screen.
    ld (ix + 13), ' '
    push ix
    push de
        ld hl, L5cbc_render_buffer
        ld (hl), 0  ; Replace "30" by a 0, so we can draw the string.
        ld ix, L725c_videomem_row_pointers + 79 * 2
        ld de, #0e27
        call Ld01c_draw_string  ; Draw savegame name
    pop de
    pop ix

    ; Check if the savegame name matches what the player entered:
    ld a, (L8129_filename_length)
    or a
    jr nz, L8291
    ; If player did not enter any name, accept any savegame:
    ld bc, 12
    add ix, bc
    jr L82a1_savegame_name_matches
L8291:
    ; Check if names match:
    ld b, 12
    ld hl, (L812a_filename_ptr)
L8296_savegame_name_check_loop:
    ld a, (ix)
    cp (hl)
    jr nz, L822a  ; If name does not match, retry
    inc ix
    inc hl
    djnz L8296_savegame_name_check_loop

L82a1_savegame_name_matches:
    ld (l812c_savegame_data_size), de
    ld a, d
    and 240
    jr nz, L8300
    ; Check that the version matches this game:
    ld e, (ix + 2)
    ld d, (ix + 3)
    ld hl, (Ld083_game_version)
    or a
    sbc hl, de
    jr nz, L8300
    ld l, (ix + 4)
    ld h, (ix + 5)
    ld (L8130_checksum), hl
    
    ld ix, L725c_videomem_row_pointers + 68 * 2
    ld hl, L7574_text_loading
    ld de, #0e27
    call Ld01c_draw_string

    ; Load savegame data:
    ld ix, L5cbc_render_buffer
    ld de, (l812c_savegame_data_size)

    ; Set the flags/values the BIOS routine expects to load:
    scf
    ld a, 255
    inc d
    ex af, af'
    dec d
    di
    call L0562_BIOS_READ_FROM_TAPE_SKIP_TESTS
    push af
        ld a, 127
        in a, (ULA_PORT)
        rra
        jr nc, L831d_done_loading_saving_pop  ; If space (break?) was pressed, cancel.
    pop af
    ld ix, L7565_text_loading_error
    jr nc, L8304

    ld de, L5cbc_render_buffer
    ld hl, (l812c_savegame_data_size)
    call L838c_checksum
    ld hl, (L8130_checksum)
    or a
    sbc hl, bc
    jr z, L8320_found_valid_savegame

L8300:
    ; Load error: version mismatch
    ld ix, L7556_text_invalid_file
L8304:
    ; Load error
    push ix
    pop hl
    ld ix, L725c_videomem_row_pointers + 68 * 2
    ld de, #0e27
    call Ld01c_draw_string
    ld hl, L7538_text_spaces
    ld ix, L725c_videomem_row_pointers + 79 * 2
    call Ld01c_draw_string
    jr L8362_done_loading_saving_with_pause

L831d_done_loading_saving_pop:
    pop af
    jr L8362_done_loading_saving_with_pause

L8320_found_valid_savegame:
    ; Found a valid savegame, restore state:
    ld hl, L5cbc_render_buffer
    ld de, L6aad_savegame_data_start
    ld bc, 119
    ldir

    ; Restore the additional area state information:
    ld a, (Ld082_n_areas)
    ld c, a
    ld iy, Ld0d1_area_offsets
L8333_area_loop:
    ld e, (iy)
    ld d, (iy + 1)
    inc iy
    inc iy
    ld ix, Ld082_area_reference_start
    add ix, de
    ld b, (ix + AREA_N_OBJECTS)
    ld de, 8
    add ix, de
L834b:
    ld a, (hl)
    ld (ix + OBJECT_TYPE_AND_FLAGS), a
    inc hl
    ld e, (ix + OBJECT_SIZE)
    add ix, de
    djnz L834b
    dec c
    jr nz, L8333_area_loop
    ei
    ld a, (L6ad7_current_border_color)
    out (ULA_PORT), a
    jr L8373_done_loading_saving

L8362_done_loading_saving_with_pause:
    ei
    ld a, (L6ad7_current_border_color)
    out (ULA_PORT), a  ; Set the border color.
    ; Wait 50 interrupts:
    ld a, 50
    ld (L74a5_interrupt_timer), a
L836d_pause_loop:
    ld a, (L74a5_interrupt_timer)
    or a
    jr nz, L836d_pause_loop

L8373_done_loading_saving:
    ld hl, #fffd
    ld (L746c_game_flags), hl
    ld a, 1
    ld (L7466_need_attribute_refresh_flag), a
    ld (L7477_render_buffer_effect), a  ; fade in effect when rendering
    call L83aa_redraw_whole_screen
    xor a
    ld (L746c_game_flags), a
    ld (L746c_game_flags + 1), a
    ret


; --------------------------------
; Calculates the check sum of a block of data.
; Input:
; - de: ptr to the data to calculate the checksum for
; - hl: length of the data
; Output:
; - bc: 16bit checksum
L838c_checksum:
    ; Initialize checksum to 0:
    xor a
    ld b, a
    ld c, a
L838f_checksum_loop:
    ; xor each pair of bytes in the data with "bc":
    ld a, (de)
    xor b
    ld b, a
    inc de
    dec hl
    ld a, l
    or h
    jr z, L83a1_checksum_done
    ld a, (de)
    xor c
    ld c, a
    inc de
    dec hl
    ld a, l
    or h
    jr nz, L838f_checksum_loop
L83a1_checksum_done:
    sla b
    rl c
    rl b
    rl c
    ret


; --------------------------------
; Redraws the whole screen, including:
; - UI elements
; - 3d view
L83aa_redraw_whole_screen:
    push ix
    push iy
    push hl
    push de
    push bc
    push af
        ld a, (L7474_check_if_object_crushed_player_flag)
        or a
        jr z, L83bf_no_need_to_check_crush
        call Lcaaa_check_if_object_crushed_player
        or a
        jp nz, L840b_update_ui_and_done
L83bf_no_need_to_check_crush:
        ld a, (L746c_game_flags)
        bit 2, a
        jr z, L83eb_no_need_to_reproject_objects
        call L8bb7_determine_rendering_volume
        call L95de_init_rotation_matrix
        xor a
        ld (L7469_n_spirits_found_in_current_area), a
        ld ix, (L7463_global_area_objects)
        ld a, (L7465_global_area_n_objects)
        or a
        call nz, L8431_project_objects
        ld ix, (L6ad1_current_area_objects)
        ld a, (L6ad0_current_area_n_objects)
        or a
        call nz, L8431_project_objects
        call L9c2d_sort_objects_for_rendering
        jr L83fe_rerender
L83eb_no_need_to_reproject_objects:
        ; If there is a lightning, re-render for sure:
        ld a, (L6b0e_lightning_time_seconds_countdown)
        or a
        jr nz, L83f7  ; if there is no lightning, rerender only if the re-render flag is set.
        ld a, (L6b19_current_area_flags)
        or a
        jr nz, L83fe_rerender
L83f7:
        ld a, (L746c_game_flags + 1)
        bit 3, a  ; check if we need to re-render.
        jr z, L840b_update_ui_and_done  ; skip re-render
L83fe_rerender:
        call Lbc52_update_UI
        call L9d46_render_3d_view
        call L9dbc_render_buffer_with_effects
        jr L840e_continue
        jr L840e_continue  ; Note: unreachable?
L840b_update_ui_and_done:
        call Lbc52_update_UI
L840e_continue:
        ; Check if we need to reprint the current room name:
        ld a, (L746c_game_flags + 1)
        bit 5, a
        jr z, L8428_done

L8415_pause_loop:
        ld a, (L74a5_interrupt_timer)
        or a
        jr nz, L8415_pause_loop
        ; Print the current room name:
        ld hl, L6abf_current_area_name_string
        ld ix, L735a_ui_message_row_pointers
        ld de, #0f00  ; string length = 15, no x offset
        call Ld01c_draw_string
L8428_done:
    pop af
    pop bc
    pop de
    pop hl
    pop iy
    pop ix
    ret


; --------------------------------
; Projects all objects from 3d coordinates to 2d coordinates, determining which ones have to be drawn.
; - When this function is called this has already happened:
;   - rendering cube volume has been calculated
;   - rotation matrix has already been set
; Input:
; - a: number of objects
; - ix: pointer to objects
L8431_project_objects:
L8431_object_loop:
    push af
        ld (L749d_object_currently_being_processed_ptr), ix
        ld a, (ix + OBJECT_TYPE_AND_FLAGS)
        and #0f
        jp z, L84fb_next_object
        bit 6, (ix + OBJECT_TYPE_AND_FLAGS)
        jp nz, L84fb_next_object
        cp 2  ; Check if it's a spirit
        jr nz, L8450_not_a_spirit
        ; It is a spirit, increment the counter of spirits found:
        ld hl, L7469_n_spirits_found_in_current_area
        inc (hl)
        jp L84fb_next_object
L8450_not_a_spirit:
        ld a, (L6abd_cull_by_rendering_volume_flag)
        or a
        jr nz, L8471_skip_rendering_volume_cull_check

        ; Rendering cube cull check:
        ; Check if the object intersects with the rendering volume:
        ld hl, L745d_rendering_cube_volume
        ld b, 3  ; 3 iterations, one for X, one for Y, one for Z
L845b_rendering_volume_cull_check_loop:
        ld a, (ix + OBJECT_X)
        cp (hl)
        jr z, L8464
        jp p, L84fb_next_object  ; Outside of rendering volume
L8464:
        add a, (ix + OBJECT_SIZE_X)
        inc hl
        cp (hl)
        jp m, L84fb_next_object  ; Outside of rendering volume
        inc ix
        inc hl
        djnz L845b_rendering_volume_cull_check_loop

        ; Passed the cull check, object intersects with the rendering volume!
L8471_skip_rendering_volume_cull_check:
        ld de, (L7499_3d_object_bounding_box_relative_to_player_ptr)
        xor a
        ld ix, (L749d_object_currently_being_processed_ptr)
        ld hl, L6aad_player_current_x
        ld b, 3
        ; This loop iterates 3 times, one for x, one for y and one for z:
        ; It is used to:
        ; - check if the player is within the bounding box defined by the object (stored in L5e62_player_collision_with_object_flags).
        ; - store the relative bounding box coordinates relative to the player in the pointer in L7499_3d_object_bounding_box_relative_to_player_ptr.
L847f_player_coordinate_loop:
        push bc
            ld c, (hl)
            inc hl
            ld b, (hl)  ; bc = player coordinate (x, y or z)
            inc hl
            push hl
                ld l, 0
                ld h, (ix + OBJECT_X)
                srl h
                rr l
                srl h
                rr l  ; hl = object coordinate * 64
                or a
                sbc hl, bc  ; hl = object coordinate * 64 - player coordinate
                jr z, L849c
                jp m, L849c
                ; player coordinate < object coordinate 1
                set 6, a
L849c:
                srl a
                ; save the object coordinate - player coordinate to (de)
                ex de, hl
                    ld (hl), e
                    inc hl
                    ld (hl), d
                    inc hl
                ex de, hl

                ld c, 0
                ld b, (ix + OBJECT_SIZE_X)
                srl b
                rr c
                srl b
                rr c  ; bc = object size * 64
                or a
                adc hl, bc  ; hl = (coordinate + size) * 64 - player coordinate
                jp p, L84b9
                ; player coordinate > object coordinate 2
                set 6, a
L84b9:
                srl a
                ; save the object coordinate 2 - player coordinate to (de)
                ex de, hl
                    ld (hl), e
                    inc hl
                    ld (hl), d
                    inc hl
                ex de, hl
                inc ix
            pop hl
        pop bc
        djnz L847f_player_coordinate_loop
        ; If player is inside of the bounding box, we will have a = #3f
        ; Each of the 6 bits represents a collision in one of the 6 directions one can collide with a cube,
        ; If this is 0, it means collision, any other thing than 0 is NO collision.
        ld (L5e62_player_collision_with_object_flags), a
        ld ix, (L749d_object_currently_being_processed_ptr)
        ld a, (ix + OBJECT_ID)
        ld (L7468_focus_object_id), a
        ld a, (ix + OBJECT_TYPE_AND_FLAGS)
        and #0f
        ld (L5e61_object_currently_being_processed_type), a
        cp OBJECT_TYPE_CUBE
        jr nz, L84e5
        call L9661_project_cube_objects
        jr L84fb_next_object
L84e5:
        cp OBJECT_TYPE_RECTANGLE
        jr nz, L84ee
        call L9b5b_project_rectangle_objects
        jr L84fb_next_object
L84ee:
        cp OBJECT_TYPE_LINE
        jp p, L84f8
        call L97bb_project_other_solids
        jr L84fb_next_object
L84f8:
        ; Objects with ID >= 10 means that they are basic shapes (line, triangle, quad, pentagon, hexagon.):
        ; - they have ID - 8 vertices in their geometry.
        call L9ac5_project_flat_shape_object
L84fb_next_object:
        ; Get the pointer to the next object, and loop:
        ld ix, (L749d_object_currently_being_processed_ptr)
        ld e, (ix + OBJECT_SIZE)
        ld d, 0
        add ix, de
    pop af
    dec a
    jp nz, L8431_object_loop
    ret


; --------------------------------
; Auxiliary variables for L850f_apply_rotation_matrix_to_object_vertices
L850c_vertex_times_matrix_24bit_accumulator:  ; 24 bit number buffer
    db #00, #00, #00


; --------------------------------
; Given object vertex coordinates already relative to the player,
; stored in (L5e63_3d_vertex_coordinates_relative_to_player), this
; method multiplies them by the rotation matrix (L5e55_rotation_matrix),
; and stores the results in (L5e9f_3d_vertex_coordinates_after_rotation_matrix).
L850f_apply_rotation_matrix_to_object_vertices:
    ld iy, L5e63_3d_vertex_coordinates_relative_to_player
    ld hl, L5e9f_3d_vertex_coordinates_after_rotation_matrix
    ld a, (L7496_current_drawing_primitive_n_vertices)
    ld c, a
L851a_vertex_loop:
    ; Multiply the vertex 3d vector by the rotation matrix:
    ld ix, L5e55_rotation_matrix
    ld b, 3
L8520_coordinate_loop:
    push hl
        ; Zero out the 24bit accumulator:
        xor a
        ld (L850c_vertex_times_matrix_24bit_accumulator), a
        ld (L850c_vertex_times_matrix_24bit_accumulator + 1), a
        ld (L850c_vertex_times_matrix_24bit_accumulator + 2), a
        ; x * matrix[b][0]
        ld a, (ix)  ; ix points to the rotation matrix
        inc ix
        or a
        jr z, L8542_multiply_by_0
        ld l, (iy)
        ld h, (iy + 1)  ; Get "x" vertex coordinate
        call La108_a_times_hl_signed
        ld (L850c_vertex_times_matrix_24bit_accumulator + 2), a
        ld (L850c_vertex_times_matrix_24bit_accumulator), hl
L8542_multiply_by_0:
        ; y * matrix[b][1]
        ld a, (ix)
        inc ix
        or a
        jr z, L8563_multiply_by_0
        ld l, (iy + 2)
        ld h, (iy + 3)  ; Get "y" vertex coordinate
        call La108_a_times_hl_signed
        ; Add to the 24 bit accumulator:
        ld de, (L850c_vertex_times_matrix_24bit_accumulator)
        add hl, de
        ld (L850c_vertex_times_matrix_24bit_accumulator), hl
        ld e, a
        ld a, (L850c_vertex_times_matrix_24bit_accumulator + 2)
        adc a, e
        ld (L850c_vertex_times_matrix_24bit_accumulator + 2), a
L8563_multiply_by_0:
        ; z * matrix[b][2]
        ld a, (ix)
        inc ix
        or a
        jr z, L8584_multiply_by_0
        ld l, (iy + 4)
        ld h, (iy + 5)  ; Get "z" vertex coordinate
        call La108_a_times_hl_signed
        ; Add to the 24 bit accumulator:
        ld de, (L850c_vertex_times_matrix_24bit_accumulator)
        add hl, de
        ld (L850c_vertex_times_matrix_24bit_accumulator), hl
        ld e, a
        ld a, (L850c_vertex_times_matrix_24bit_accumulator + 2)
        adc a, e
        ld (L850c_vertex_times_matrix_24bit_accumulator + 2), a
L8584_multiply_by_0:
        ld hl, (L850c_vertex_times_matrix_24bit_accumulator)
        ld a, (L850c_vertex_times_matrix_24bit_accumulator + 2)
        ; (a, e) = (a, hl) / 64
        add hl, hl
        rla
        add hl, hl
        rla
        ld e, h
    pop hl
    ld (hl), e
    inc hl
    ld (hl), a
    inc hl
    djnz L8520_coordinate_loop
    ; next vertex:
    ld de, 6
    add iy, de
    dec c
    jp nz, L851a_vertex_loop
    ret


; --------------------------------
; Auxiliary variables for L85ae_clip_edge
L85a0_vertex1_coordinates:
    dw #0000, #0000, #0000
L85a6_vertex2_coordinates:
    dw #0000, #0000, #0000
L85ac_vertex_frustum_checks:
    db #00, #00


; --------------------------------
; This function clips an edge to make sure both vertices are inside of the viewing area.
; - If both fail the same frustum visibility check, the edge is discarded.
; - Otherwise, for each failed test, a point that intersects with the viewing volume is calculated and the
;   point that was outside of the volume is replaced.
; - At the end, if all 5 frustum checks were able to be successfully passed, the points are
;   projected.
; Note: I think this method contains several bugs, that might be hard to detect, as
;       they might only show up in certain corner cases. But this should be verified.
;       I am, of course, not 100% sure.
; Input:
; - ix: ptr to "L5ee8_already_projected_vertex_coordinates" entry for this edge (+ 1)
; - hl: pointer to 3d vertex 1 (after rotation matrix)
; - iy: pointer to 3d vertex 2 (after rotation matrix)
; - c: frustum checks of vertex 1
; - b: frustum checks of vertex 2
L85ae_clip_edge:
    ; Save the vertex info to local variables:
    ld (L85ac_vertex_frustum_checks), bc
    ld bc, 6
    ld de, L85a0_vertex1_coordinates
    ldir
    ld c, 6
    push iy
    pop hl
    ldir

    push ix
    pop iy  ; iy = ptr to "L5ee8_already_projected_vertex_coordinates" entry for this edge (+ 1)
    ld bc, (L85ac_vertex_frustum_checks)
    bit 0, c
    jr nz, L85d4
    ; First vertex is behind the camera
    bit 0, b
    jp z, L88cb_mark_as_processed_and_return  ; if both are behind the camera, this edge projects no points.
    jr L85d9

L85d4:
    ; First point is in front of the camera
    bit 0, b
    jp nz, L8666

L85d9:
    ; One point is behind the camera, and one in front:
    ld hl, (L85a0_vertex1_coordinates + 2*2)  ; hl = v1.z
    ld de, (L85a6_vertex2_coordinates + 2*2)  ; de = v2.z
    xor a
    sbc hl, de  ; hl = (v1.z - v2.z)
    push hl
        ld b, h  ; bc = (v1.z - v2.z)
        ld c, l
        ld hl, (L85a6_vertex2_coordinates)  ; hl = v1.x
        ld de, (L85a0_vertex1_coordinates)  ; de = v2.x
        or a
        sbc hl, de  ; hl = v1.x - v2.x
        ld de, (L85a0_vertex1_coordinates + 2*2)  ; d2 = v1.z
        call La15e_de_times_hl_signed  ; (de, hl) = v1.z * (v1.x - v2.x)
        call Lb1b7_de_hl_divided_by_bc_signed  ; (de, hl) = (v1.z * (v1.x - v2.x)) / (v1.z - v2.z)
        ld de, (L85a0_vertex1_coordinates)  ; v1.x
        add hl, de  ; hl = v1.z * (v1.x - v2.x) / (v1.z - v2.z) + v1.x
    pop bc  ; bc = (v1.z - v2.z)
    push hl
        ld hl, (L85a6_vertex2_coordinates + 1*2)
        ld de, (L85a0_vertex1_coordinates + 1*2)
        or a
        sbc hl, de  ; hl = v2.y - v1.y
        ld de, (L85a0_vertex1_coordinates + 2*2)
        call La15e_de_times_hl_signed  ; (de, hl) = v1.z * (v2.y - v1.y)
        call Lb1b7_de_hl_divided_by_bc_signed  ; (de, hl) = v1.z * (v2.y - v1.y) / (v1.z - v2.z)
        ld de, (L85a0_vertex1_coordinates + 1*2)
        add hl, de  ; (de, hl) = v1.z * (v2.y - v1.y) / (v1.z - v2.z) + v1.y
        ld de, 0
        ld a, (L85ac_vertex_frustum_checks)
        bit 0, a
        jr nz, L8631_overwrite_vertex2
        ; Overwrite vertex 1:
        ; BUG? I think y and z are flipped here and this is wrongly calculated
        ld (L85a0_vertex1_coordinates + 1*2), hl  ; v1.y = 0
    pop hl
    ld (L85a0_vertex1_coordinates), hl  ; v1.x = v1.z * (v1.x - v2.x) / (v1.z - v2.z) + v1.x
    ld (L85a0_vertex1_coordinates + 2*2), de  ; v1.z = v1.z * (v2.y - v1.y) / (v1.z - v2.z) + v1.y
    jr L863c_both_vertices_in_front_of_camera
L8631_overwrite_vertex2:
    ; BUG? I think y and z are flipped here and this is wrongly calculated
    ld (L85a6_vertex2_coordinates + 1*2), hl
    pop hl
    ld (L85a6_vertex2_coordinates), hl
    ld (L85a6_vertex2_coordinates + 2*2), de

L863c_both_vertices_in_front_of_camera:
    ; Update bit 1 of the frustum checks for the new points:
    ld bc, (L85ac_vertex_frustum_checks)
    ; BUG? bit "1" was "x - z" check in "L9246_object_visibility_check", but here
    ;      the code is doing "y - z" instead, which should be bit 2.
    set 1, b
    set 1, c
    ld hl, (L85a0_vertex1_coordinates + 2*2)  ; v1.z
    ld de, (L85a0_vertex1_coordinates + 1*2)  ; v1.y
    or a
    sbc hl, de  ; hl = v1.y - v1.z
    jp p, L8653
    res 1, c
L8653:
    ld hl, (L85a6_vertex2_coordinates + 2*2)  ; v2.z
    ld de, (L85a6_vertex2_coordinates + 1*2)  ; v2.y
    or a
    sbc hl, de  ; hl = v2.y - v2.z
    jp p, L8662
    res 1, b
L8662:
    ld (L85ac_vertex_frustum_checks), bc

    ; The remainder of this function is made out of 4 blocks analogous to the one above,
    ; in each block, if both vertexes are found to fail the same frustum check, the edge is
    ; ignored, otherwise, if only one of them fails it, a point that intersects with the plane
    ; that defines the frustum check in question is found, and the point that failed the check 
    ; is overwritten. This is done for all 4 remaining frustum checks, and at the end, 
    ; we can be sure that both points are inside the viewing area.
    ; Ensure both vertices pass frustum check 1:
L8666:
    bit 1, c
    jr nz, L8671
    bit 1, b
    jp z, L88cb_mark_as_processed_and_return
    jr L8676
L8671:
    bit 1, b
    jp nz, L86e6_both_vertices_pass_frustum_check1
L8676:
    ld hl, (L85a0_vertex1_coordinates + 2*2)
    ld de, (L85a0_vertex1_coordinates + 1*2)
    xor a
    sbc hl, de
    push hl
    ld hl, (L85a6_vertex2_coordinates + 1*2)
    ld ix, L86b3
L8688:
    xor a
    sbc hl, de
    ld de, (L85a6_vertex2_coordinates + 2*2)
    xor a
    sbc hl, de
    ld de, (L85a0_vertex1_coordinates + 2*2)
    add hl, de
    ld b, h
    ld c, l
    ld hl, (L85a6_vertex2_coordinates + 2*2)
    or a
    sbc hl, de
    pop de
    push de
    push bc
    call La15e_de_times_hl_signed
    call Lb1b7_de_hl_divided_by_bc_signed
    ld de, (L85a0_vertex1_coordinates + 2*2)
    add hl, de
    pop bc
    pop de
    push hl
    push de
    jp ix
L86b3:
    ld hl, (L85a6_vertex2_coordinates)
    ld de, (L85a0_vertex1_coordinates)
    xor a
    sbc hl, de
    pop de
    call La15e_de_times_hl_signed
    call Lb1b7_de_hl_divided_by_bc_signed
    ld de, (L85a0_vertex1_coordinates)
    add hl, de
    ld a, (L85ac_vertex_frustum_checks)
    bit 1, a
    jr nz, L86dc
    ld (L85a0_vertex1_coordinates), hl
    pop hl
    ld (L85a0_vertex1_coordinates + 1*2), hl
    ld (L85a0_vertex1_coordinates + 2*2), hl
    jr L86e6_both_vertices_pass_frustum_check1
L86dc:
    ld (L85a6_vertex2_coordinates), hl
    pop hl
    ld (L85a6_vertex2_coordinates + 1*2), hl
    ld (L85a6_vertex2_coordinates + 2*2), hl

L86e6_both_vertices_pass_frustum_check1:
    ; BUG? Same as above, I think these are flipped!
    ;      bit "2" was "y - z" check in "L9246_object_visibility_check", but here
    ;      the code is doing "x - z" instead, which should be bit 1.
    ld bc, (L85ac_vertex_frustum_checks)
    set 2, b
    set 2, c
    ld hl, (L85a0_vertex1_coordinates + 2*2)  ; v1.z
    ld de, (L85a0_vertex1_coordinates)  ; v1.x
    or a
    sbc hl, de
    jp p, L86fd
    res 2, c
L86fd:
    ld hl, (L85a6_vertex2_coordinates + 2*2)  ; v2.z
    ld de, (L85a6_vertex2_coordinates)  ; v2.x
    or a
    sbc hl, de
    jp p, L870c
    res 2, b
L870c:
    ld (L85ac_vertex_frustum_checks), bc
    bit 2, c
    jr nz, L871b
    bit 2, b
    jp z, L88cb_mark_as_processed_and_return
    jr L8720
L871b:
    bit 2, b
    jp nz, L8768_both_vertices_pass_frustum_check2
L8720:
    ld hl, (L85a0_vertex1_coordinates + 2*2)
    ld de, (L85a0_vertex1_coordinates)
    xor a
    sbc hl, de
    push hl
    ld hl, (L85a6_vertex2_coordinates)
    ld ix, L8735
    jp L8688
L8735:
    ld hl, (L85a6_vertex2_coordinates + 1*2)
    ld de, (L85a0_vertex1_coordinates + 1*2)
    xor a
    sbc hl, de
    pop de
    call La15e_de_times_hl_signed
    call Lb1b7_de_hl_divided_by_bc_signed
    ld de, (L85a0_vertex1_coordinates + 1*2)
    add hl, de
    ld a, (L85ac_vertex_frustum_checks)
    bit 2, a
    jr nz, L875e
    ld (L85a0_vertex1_coordinates + 1*2), hl
    pop hl
    ld (L85a0_vertex1_coordinates), hl
    ld (L85a0_vertex1_coordinates + 2*2), hl
    jr L8768_both_vertices_pass_frustum_check2
L875e:
    ld (L85a6_vertex2_coordinates + 1*2), hl
    pop hl
    ld (L85a6_vertex2_coordinates), hl
    ld (L85a6_vertex2_coordinates + 2*2), hl

L8768_both_vertices_pass_frustum_check2:
    ld bc, (L85ac_vertex_frustum_checks)
    set 3, b
    set 3, c
    ld hl, (L85a0_vertex1_coordinates + 2*2)  ; v1.z
    ld de, (L85a0_vertex1_coordinates + 1*2)  ; v1.y
    or a
    adc hl, de
    jp p, L877f
    res 3, c
L877f:
    ld hl, (L85a6_vertex2_coordinates + 2*2)  ; v2.z
    ld de, (L85a6_vertex2_coordinates + 1*2)  ; v2.y
    or a
    adc hl, de
    jp p, L878e
    res 3, b
L878e:
    ld (L85ac_vertex_frustum_checks), bc
    bit 3, c
    jr nz, L879d
    bit 3, b
    jp z, L88cb_mark_as_processed_and_return
    jr L87a2
L879d:
    bit 3, b
    jp nz, L881b_both_vertices_pass_frustum_check3
L87a2:
    ld hl, (L85a0_vertex1_coordinates + 2*2)
    ld de, (L85a0_vertex1_coordinates + 1*2)
    add hl, de
    push hl
    ld hl, (L85a6_vertex2_coordinates + 1*2)
    ld ix, L87de
L87b2:
    ex de, hl
    xor a
    sbc hl, de
    ld de, (L85a6_vertex2_coordinates + 2*2)
    xor a
    sbc hl, de
    ld de, (L85a0_vertex1_coordinates + 2*2)
    add hl, de
    ld b, h
    ld c, l
    ld hl, (L85a6_vertex2_coordinates + 2*2)
    or a
    sbc hl, de
    pop de
    push de
    push bc
    call La15e_de_times_hl_signed
    call Lb1b7_de_hl_divided_by_bc_signed
    ld de, (L85a0_vertex1_coordinates + 2*2)
    add hl, de
    pop bc
    pop de
    push hl
    push de
    jp ix
L87de:
    ld hl, (L85a6_vertex2_coordinates)
    ld de, (L85a0_vertex1_coordinates)
    xor a
    sbc hl, de
    pop de
    call La15e_de_times_hl_signed
    call Lb1b7_de_hl_divided_by_bc_signed
    ld de, (L85a0_vertex1_coordinates)
    add hl, de
    pop de
    ld a, e
    cpl
    ld c, a
    ld a, d
    cpl
    ld b, a
    inc bc
    ld a, (L85ac_vertex_frustum_checks)
    bit 3, a
    jr nz, L8810
    ld (L85a0_vertex1_coordinates), hl
    ld (L85a0_vertex1_coordinates + 1*2), bc
    ld (L85a0_vertex1_coordinates + 2*2), de
    jr L881b_both_vertices_pass_frustum_check3
L8810:
    ld (L85a6_vertex2_coordinates), hl
    ld (L85a6_vertex2_coordinates + 1*2), bc
    ld (L85a6_vertex2_coordinates + 2*2), de

L881b_both_vertices_pass_frustum_check3:
    ld bc, (L85ac_vertex_frustum_checks)
    set 4, b
    set 4, c
    ld hl, (L85a0_vertex1_coordinates + 2*2)
    ld de, (L85a0_vertex1_coordinates)
    or a
    adc hl, de
    jp p, L8832
    res 4, c
L8832:
    ld hl, (L85a6_vertex2_coordinates + 2*2)
    ld de, (L85a6_vertex2_coordinates)
    or a
    adc hl, de
    jp p, L8841
    res 4, b
L8841:
    ld (L85ac_vertex_frustum_checks), bc
    bit 4, c
    jr nz, L8850
    bit 4, b
    jp z, L88cb_mark_as_processed_and_return
    jr L8855
L8850:
    bit 4, b
    jp nz, L88a5_both_vertices_pass_frustum_check4
L8855:
    ld hl, (L85a0_vertex1_coordinates + 2*2)
    ld de, (L85a0_vertex1_coordinates)
    add hl, de
    push hl
    ld hl, (L85a6_vertex2_coordinates)
    ld ix, L8868
    jp L87b2
L8868:
    ld hl, (L85a6_vertex2_coordinates + 1*2)
    ld de, (L85a0_vertex1_coordinates + 1*2)
    xor a
    sbc hl, de
    pop de
    call La15e_de_times_hl_signed
    call Lb1b7_de_hl_divided_by_bc_signed
    ld de, (L85a0_vertex1_coordinates + 1*2)
    add hl, de
    pop de
    ld a, e
    cpl
    ld c, a
    ld a, d
    cpl
    ld b, a
    inc bc
    ld a, (L85ac_vertex_frustum_checks)
    bit 4, a
    jr nz, L889a
    ld (L85a0_vertex1_coordinates), bc
    ld (L85a0_vertex1_coordinates + 1*2), hl
    ld (L85a0_vertex1_coordinates + 2*2), de
    jr L88a5_both_vertices_pass_frustum_check4
L889a:
    ld (L85a6_vertex2_coordinates), bc
    ld (L85a6_vertex2_coordinates + 1*2), hl
    ld (L85a6_vertex2_coordinates + 2*2), de

L88a5_both_vertices_pass_frustum_check4:
    ; We are done clipping the edge, now project whichever vertex needs
    ; projecting:
    ld a, #ff
    cp (iy)
    jr nz, L88b9
    ; Vertex 1 needs projecting:
    ld ix, L85a0_vertex1_coordinates
    call L90fc_project_one_vertex
    ld (iy), c  ; x
    ld (iy + 1), b  ; y
L88b9:
    cp (iy + 2)
    jr nz, L88cb_mark_as_processed_and_return
    ; Vertex 2 needs projecting:
    ld ix, L85a6_vertex2_coordinates
    call L90fc_project_one_vertex
    ld (iy + 2), c  ; x
    ld (iy + 3), b  ; y
L88cb_mark_as_processed_and_return:
    ld a, 1
    ld (iy - 1), a  ; mark edge as processed
    ret


; --------------------------------
; Checks if the normal of a face points away from the camera (and potentially we do not need to draw the face).
; Input:
; - iy: pointer to the vertex indexes of this face
; Output:
; - a: 1 (back face), 0 (front face).
; - carry flag set (same as "a"): back face.
L88d1_normal_direction_check:
    push ix
    push hl
    push de
    push bc
        ld ix, (L5f24_shape_edges_ptr)
        inc ix  ; skip the number of edges
        push ix
            ld a, (iy)
            ld l, a
            and #7f  ; get the index (remove a potential flag in the msb)
            ld c, a
            ld b, 0
            sla c
            add ix, bc  ; ix = ptr to the edge
            ld c, (ix)  ; c = vertex index 1
            ld a, (ix + 1)  ; a = vertex index 2
            bit 7, l  ; vertex index flag check
            jr z, L88f8
            ; Invert the vertexes in the current edge:
            ld h, c
            ld c, a
            ld a, h
L88f8:
            ld hl, L5e9f_3d_vertex_coordinates_after_rotation_matrix
            sla c
            add hl, bc
            sla c
            add hl, bc  ; hl += 6 * vertex index 1
            ld de, L5e63_3d_vertex_coordinates_relative_to_player
            ; Copy vertex 1:
            ld c, 6
            ldir
            ld c, a
            ld hl, L5e9f_3d_vertex_coordinates_after_rotation_matrix
            sla c
            add hl, bc
            sla c
            add hl, bc  ; hl += 6 * vertex index 2
            ; Copy vertex 2:
            ld c, 6
            ldir
            ld a, (iy + 1)
            ld l, a
            and #7f  ; get the index (remove a potential flag in the msb)
        pop ix
        ld c, a
        sla c
        add ix, bc  ; ix = ptr to the edge
        ld c, (ix)
        bit 7, l
        jr nz, L892d
        ld c, (ix + 1)  ; if edge flip flag is 1, get the other vertex.
L892d:
        ld hl, L5e9f_3d_vertex_coordinates_after_rotation_matrix
        sla c
        add hl, bc
        sla c
        add hl, bc  ; hl += 6 * vertex index 1
        ; Copy vertex 3:
        ld c, 6
        ldir

        ; At this point we have picked the first 3 vertices of the face.
        ; We now calculate the normal vector:
        ; OPTIMIZATION: faces should have the normal pre-calculated, rather than doing all this calculation each time.
        ;   Just one additional point to be ran through the rotation matrix, and we avoid all of this.
        ld h, b
        ld l, c  ; hl = 0
        ld (L5e75_48_bit_accumulator), hl
        ld (L5e75_48_bit_accumulator + 2), hl
        ld (L5e75_48_bit_accumulator + 4), hl
        ld hl, (L5e63_3d_vertex_coordinates_relative_to_player + 2*2)  ; z vertex 1
        ld de, (L5e63_3d_vertex_coordinates_relative_to_player + 5*2)  ; z vertex 2
        or a
        sbc hl, de  ; hl = z1 - z2
        push hl
            ld hl, (L5e63_3d_vertex_coordinates_relative_to_player + 7*2)  ; y vertex 3
            ld de, (L5e63_3d_vertex_coordinates_relative_to_player + 4*2)  ; y vertex 2
            or a
            sbc hl, de  ; hl = y3 - y2
        pop de
        call La15e_de_times_hl_signed  ; (de, hl) = (z1 - z2) * (y3 - y2)
        push de
            push hl
                ld hl, (L5e63_3d_vertex_coordinates_relative_to_player + 1*2)  ; y vertex 1
                ld de, (L5e63_3d_vertex_coordinates_relative_to_player + 4*2)  ; y vertex 2
                or a
                sbc hl, de
                push hl
                    ld hl, (L5e63_3d_vertex_coordinates_relative_to_player + 8*2)  ; z vertex 3
                    ld de, (L5e63_3d_vertex_coordinates_relative_to_player + 5*2)  ; z vertex 2
                    or a
                    sbc hl, de
                pop de
                call La15e_de_times_hl_signed
            pop bc
            xor a
            sbc hl, bc
        pop bc
        ex de, hl
            sbc hl, bc
        ex de, hl
        ld bc, (L5e63_3d_vertex_coordinates_relative_to_player + 3*2)  ; x vertex 2
        call L8a30_48bitmul_add
        ld hl, (L5e63_3d_vertex_coordinates_relative_to_player)  ; x vertex 1
        ld de, (L5e63_3d_vertex_coordinates_relative_to_player + 3*2)  ; x vertex 2
        or a
        sbc hl, de
        push hl
            ld hl, (L5e63_3d_vertex_coordinates_relative_to_player + 8*2)  ; z vertex 3
            ld de, (L5e63_3d_vertex_coordinates_relative_to_player + 5*2)  ; z vertex 2
            or a
            sbc hl, de
        pop de
        call La15e_de_times_hl_signed
        push de
            push hl
                ld hl, (L5e63_3d_vertex_coordinates_relative_to_player + 2*2)  ; z vertex 1
                ld de, (L5e63_3d_vertex_coordinates_relative_to_player + 5*2)  ; z vertex 2
                or a
                sbc hl, de
                push hl
                    ld hl, (L5e63_3d_vertex_coordinates_relative_to_player + 6*2)  ; x vertex 3
                    ld de, (L5e63_3d_vertex_coordinates_relative_to_player + 3*2)  ; x vertex 2
                    or a
                    sbc hl, de
                pop de
                call La15e_de_times_hl_signed
            pop bc
            xor a
            sbc hl, bc
        pop bc
        ex de, hl
        sbc hl, bc
        ex de, hl
        ld bc, (L5e63_3d_vertex_coordinates_relative_to_player + 4*2)
        call L8a30_48bitmul_add
        ld hl, (L5e63_3d_vertex_coordinates_relative_to_player + 2)
        ld de, (L5e63_3d_vertex_coordinates_relative_to_player + 4*2)
        or a
        sbc hl, de
        push hl
            ld hl, (L5e63_3d_vertex_coordinates_relative_to_player + 6*2)
            ld de, (L5e63_3d_vertex_coordinates_relative_to_player + 3*2)
            or a
            sbc hl, de
        pop de
        call La15e_de_times_hl_signed  ; (de, hl) = (z v1 - y v2) * (x v3 - x v2)
        push de
            push hl
                ld hl, (L5e63_3d_vertex_coordinates_relative_to_player)
                ld de, (L5e63_3d_vertex_coordinates_relative_to_player + 3*2)
                or a
                sbc hl, de
                push hl
                    ld hl, (L5e63_3d_vertex_coordinates_relative_to_player + 7*2)
                    ld de, (L5e63_3d_vertex_coordinates_relative_to_player + 4*2)
                    or a
                    sbc hl, de
                pop de
                call La15e_de_times_hl_signed  ; (de, hl) = (x v1 - x v2) * (y v3 - y v2)
            pop bc
            xor a
            sbc hl, bc
        pop bc
        ex de, hl
        sbc hl, bc  ; hl = (z v1 - y v2) * (x v3 - x v2) - (x v1 - x v2) * (y v3 - y v2)
        push hl
            ex de, hl
            ld bc, (L5e63_3d_vertex_coordinates_relative_to_player + 5*2)
            call L8a30_48bitmul_add
        pop hl
        ld a, (L5e75_48_bit_accumulator + 5)

        ; Check if the normal points forward or backwards:
        ; At this point:
        ; - a: has the most significant byte of the accumulator (to get the sign of the z coordinate of the normal).
        ; - hl: most significant word of "(x v1 - x v2) * (y v3 - y v2) - (z v1 - y v2) * (x v3 - x v2)"
        ld l, a
        xor h
        jp p, L8a1f
        ; We get here if the "normal z" has the same sign as "(x v1 - x v2) * (y v3 - y v2) - (z v1 - y v2) * (x v3 - x v2)".
        ; This gives the face a chance to be drawn if when projected to the screen no vertices fall inside of the view area,
        ; and the code will check if it's that the face is too big and covers the whole screen.
        ; Note: I am not sure of what the math means here, as I have not tried to derive what the value of the calculation
        ;       means.
        xor a
        ld (L5f28_cull_face_when_no_projected_vertices), a
L8a1f:
        ld a, l
        or a
        jp p, L8a27
        ; Normal points towrads the camera, this is a front face.
        xor a
        jr L8a2a
L8a27:
        ; Normal points away from camera, this is a back face.
        ld a, 1
        scf
L8a2a:
    pop bc
    pop de
    pop hl
    pop ix
    ret


; --------------------------------
; Performs the following operation:
; - First, calculate the multiplication bc * (bc, hl)
; - Then add the 48 bit result to the 48 bit number in (L5e75_48_bit_accumulator)
; - Result is saved in (L5e75_48_bit_accumulator)
; The signed 32 bit result is returned in (DE,HL)
; Input:
; - bc
; - (de, hl)
; - 6 bytes in (L5e75_48_bit_accumulator)
; Output:
; - 6 bytes in (L5e75_48_bit_accumulator)
L8a30_48bitmul_add:
    bit 7, d
    jr z, L8a48_de_hl_positive
    ; if (de, hl) is negative, calculate the absolute value:
    ld a, h
    cpl
    ld h, a
    ld a, l
    cpl
    ld l, a
    ld a, d
    cpl
    ld d, a
    ld a, e
    cpl
    ld e, a

    inc hl
    ld a, l
    or h
    ld a, 1  ; mark that we changed the sign
    jr nz, L8a48_de_hl_positive
    inc de
L8a48_de_hl_positive:
    bit 7, b
    jr z, L8a57_bc_positive
    ; if bc is negative, calculate the absolute value:
    push af
        ld a, b
        cpl
        ld b, a
        ld a, c
        cpl
        ld c, a
        inc bc
    pop af
    xor 1  ; mark that we changed the sign (if we changed the sign of only one of bc, or (de, hl), a = 1).
L8a57_bc_positive:
    ; Perform a multiplciation in the following way:
    ;    de hl
    ;  *    bc
    ;  -------
    ;    AA BB <- bc * hl
    ; CC DD
    ; --------
    ; hl bc de
    push de
        ld e, c
        ld d, b
        call L8ab4_de_times_hl_signed  ; (AA, BB) = hl * bc
        ; We temporarily save the result in RAM:
        ld (L5e7b_48bitmul_tmp1), hl  ; save BB
        ld (L5e7d_48bitmul_tmp2), de  ; save AA
    pop de
    ld l, c
    ld h, b
    call L8ab4_de_times_hl_signed  ; (CC, DD) = de * bc
    ld bc, (L5e7d_48bitmul_tmp2)  ; recover AA
    add hl, bc  ; AA + DD
    ld b, h
    ld c, l  ; bc = AA + DD
    ld hl, 0
    adc hl, de  ; hl = CC + (carry of AA + DD)
    ld de, (L5e7b_48bitmul_tmp1)  ; recover BB
    ; At this point (hl, bc, de) has the absolute value of the 48 bit result of the multiplication
    ; Check if we need to change the sign of the result:
    or a
    jr z, L8a9a_result_is_positive
    ; Make the result negative:
    ld a, h
    cpl
    ld h, a
    ld a, l
    cpl
    ld l, a
    ld a, b
    cpl
    ld b, a
    ld a, c
    cpl
    ld c, a
    ld a, d
    cpl
    ld d, a
    ld a, e
    cpl
    ld e, a
    inc de
    ld a, e
    or d
    jr nz, L8a9a_result_is_positive
    inc bc
    ld a, c
    or b
    jr nz, L8a9a_result_is_positive
    inc hl
L8a9a_result_is_positive:
    ; At this point (hl, bc, de) has the 48 bit result of the multiplication
    ; Add this 48 bit number with the 48 bit number stored in (L5e75_48_bit_accumulator)
    push hl
        ld hl, (L5e75_48_bit_accumulator)
        add hl, de
        ld (L5e75_48_bit_accumulator), hl
        ld hl, (L5e75_48_bit_accumulator + 2)
        adc hl, bc
        ld (L5e75_48_bit_accumulator + 2), hl
        ld hl, (L5e75_48_bit_accumulator + 4)
    pop bc
    adc hl, bc
    ld (L5e75_48_bit_accumulator + 4), hl
    ret


; --------------------------------
; Signed multiplication between DE and HL.
; The signed 32 bit result is returned in (DE,HL)
; Input:
; - de
; - hl
; Output:
; - de, hl
L8ab4_de_times_hl_signed:
    push bc
    push af
        ld a, h
        ld c, l
        ld b, 16
        ld hl, 0
L8abd:
        sla c
        rla
        jr c, L8ace
        djnz L8abd
        ld d, b
        ld e, b
        jr L8ad9
L8ac8:
        add hl, hl
        rl c
        rla
        jr nc, L8ad5
L8ace:
        add hl, de
        jr nc, L8ad5
        inc c
        jr nz, L8ad5
        inc a
L8ad5:
        djnz L8ac8
        ld d, a
        ld e, c
L8ad9:
    pop af
    pop bc
    ret


; --------------------------------
; Projects an object, and if it falls within the screen, add it to the list of objects to draw,
; assuming that all vertexes are in screen (if a single one is out, whole object is discarted)
; Input:
; - iy: face definition ptr:
;   - first byte is number of faces
;   - then, each face has:
;     - attribute
;     - number of vertices
;     - then one byte per vertex (index)
L8adc_project_object_and_add_to_render_list_internal:
    ld a, (L7496_current_drawing_primitive_n_vertices)
    ld b, a
    ; Initialize the L5ee8_already_projected_vertex_coordinates array:
    ; Since different edges might share vertexes, when we project a vertex,
    ; we mark it in this array, to prevent projecting them again.
    ld hl, L5ee8_already_projected_vertex_coordinates
    ld a, #ff  ; mark that a vertex has not been projected.
L8ae5:
    ld (hl), a
    inc hl
    inc hl
    djnz L8ae5

    xor a
    ld (L5e5f_add_to_projected_objects_flag), a
    ld hl, (L7497_next_projected_vertex_ptr)
    ld a, (L7468_focus_object_id)
    ; Start writing the projected vertex data:
    ld (hl), a  ; object ID
    inc hl
    ld (hl), 0  ; number of primitives (init to zero, and will be incremented each time a face is added).
    inc hl
    ld b, (iy)  ; number of faces
    inc iy
L8afe_face_loop:
    push bc
        ld a, (iy)  ; a = texture ID.
        inc iy
        ld b, (iy)  ; b = number of vertices in the face.
        inc iy
        ; If it's a transparent face, ignore:
        or a
        jr z, L8b24_skip_face_bytes_and_next_face
        sla a
        sla a
        sla a
        sla a
        ld c, a
        ld a, (L5e60_projection_pre_work_type)
        ;   - if a == 0: indicates that vertices can be projected directly.
        ;   - if a == 1: we need to call L88d1_normal_direction_check before projection, and if back-face, we cull
        ;   - if a == 2: we need to call L88d1_normal_direction_check before projection, and if back-face we need to use L5f26_alternative_shape_edges_ptr
        or a
        jr z, L8b50_ready_to_project
        cp 1
        jr nz, L8b2c

        ; Normal check, and cull if failed:
        call L88d1_normal_direction_check
        jr nc, L8b50_ready_to_project
        ; back face!
L8b24_skip_face_bytes_and_next_face:
        ld c, b
        ld b, 0
        add iy, bc
        jp L8bb1_next_face

L8b2c:
        call L88d1_normal_direction_check
        ld a, (L746a_current_drawing_texture_id)
        jr nc, L8b43
        ; back face, we need to swap texture ID, and use alternative shape edges ptr:
        and #f0
        jr z, L8b24_skip_face_bytes_and_next_face
        ld c, a
        ld de, (L5f26_alternative_shape_edges_ptr)
        ld (L5f24_shape_edges_ptr), de
        jr L8b50_ready_to_project

L8b43:
        and #0f
        jr z, L8b24_skip_face_bytes_and_next_face
        sla a
        sla a
        sla a
        sla a
        ld c, a
L8b50_ready_to_project:
        ; At this point:
        ; - b: number of vertices
        ; - c: texture ID (in the most significant 4 bits)
        ; - hl: pointer to the resulting projected vertex data (about to write texture byte)
        ; - iy: ptr to the face vertex indexes
        ld a, c
        or b
        ld (hl), a  ; save # vertices and texture ID
        inc hl
L8b54_vertex_loop:
        push bc
            ld a, (iy)  ; edge index
            and #7f  ; get the index (remove a potential flag in the msb)
            sla a
            ld c, a
            ld b, 0
            ld ix, (L5f24_shape_edges_ptr)
            inc ix  ; skip the number of edges
            add ix, bc  ; ix = ptr to the edge
            bit 7, (iy)
            jr z, L8b6f
            inc ix  ; If the msb flag is set, we invert the vertex in the edge
L8b6f:
            inc iy  ; next index
            ld c, (ix)  ; get the vertex index
            sla c  ; vertex index * 2
            ld ix, L5ee8_already_projected_vertex_coordinates
            add ix, bc
            ld a, (ix)
            ; Check if we have already projected the vertex:
            cp #ff
            jr nz, L8b9b_already_projected
            ; We have not projected it yet, so, we project it now:
            push ix
                ld ix, L5e9f_3d_vertex_coordinates_after_rotation_matrix
                add ix, bc
                add ix, bc
                add ix, bc
                call L90fc_project_one_vertex
            pop ix
            ; Save the projected coordinates (c, b) to the temporary L5ee8_already_projected_vertex_coordinates array.
            ld (ix), c
            ld (ix + 1), b
            ld a, c  ; a = projected x
L8b9b_already_projected:
            ; Write the projected coordiantes to the projected vertices data for rendering:
            ld (hl), a  ; x
            inc hl
            ld a, (ix + 1)  ; y
            ld (hl), a
            inc hl
        pop bc
        djnz L8b54_vertex_loop

        ld a, 1
        ld (L5e5f_add_to_projected_objects_flag), a
        ld ix, (L7497_next_projected_vertex_ptr)
        inc (ix + 1)  ; increment the number of primitives counter
L8bb1_next_face:
    pop bc
    dec b
    jp nz, L8afe_face_loop
    ret


; --------------------------------
; Sets the rendering volume, a cube (to prune which objects to render).
L8bb7_determine_rendering_volume:
    ld a, (L6abd_cull_by_rendering_volume_flag)  ; if we are not culling by volume, just return
    or a
    ret nz
    ; Clear the L745d_rendering_cube_volume to #ff:
    ld hl, L745d_rendering_cube_volume
    ld b, 6
    dec a
L8bc2_clear_memory_loop:
    ld (hl), a  ; a == #ff here
    inc hl
    djnz L8bc2_clear_memory_loop

    ; This loop is executed 4 times, each time adjusting the
    ; pitch/yaw andles up or down by 8 units, and each time,
    ; the values in L745d_rendering_cube_volume are being set: 
    ld h, 4
    ld ix, L745d_rendering_cube_volume
L8bcc_angle_loop:
    ld a, h  ; h is the iteration index (4, 3, 2, 1)
    cp 3
    ld a, (L6ab7_player_yaw_angle)
    jr nc, L8bde
    ; Iterations 1, 2:
    ; If we are too close to the upper limit, wrap around
    add a, 8
    cp FULL_ROTATION_DEGREES
    jr c, L8be4_yaw_set
    sub FULL_ROTATION_DEGREES
    jr L8be4_yaw_set
L8bde:
    ; Iterations 3, 4:
    ; If we are too close to the lower limit, wrap around
    sub 8
    jr nc, L8be4_yaw_set
    add a, FULL_ROTATION_DEGREES
L8be4_yaw_set:
    ; Here we have a = (L6ab7_player_yaw_angle)
    ld b, a
    bit 0, h
    ld a, (L6ab6_player_pitch_angle)
    jr z, L8bf6
    ; Iterations 1 and 3:
    add a, 8
    cp FULL_ROTATION_DEGREES
    jr c, L8bfc_pitch_set
    sub FULL_ROTATION_DEGREES
    jr L8bfc_pitch_set
L8bf6:
    ; Iterations 2 and 4:
    sub 8
    jr nc, L8bfc_pitch_set
    add a, FULL_ROTATION_DEGREES
L8bfc_pitch_set:
    ld c, a
    ; Here: b = yaw, c = pitch.
    ld a, b
    cp FULL_ROTATION_DEGREES/4
    jr nc, L8c06
    ld d, 1
    jr L8c18
L8c06:
    cp FULL_ROTATION_DEGREES/2
    jr nc, L8c0e
    ld d, 3
    jr L8c18
L8c0e:
    cp 3*FULL_ROTATION_DEGREES/4
    jr nc, L8c16
    ld d, 5
    jr L8c18
L8c16:
    ld d, 7
L8c18:
    ld a, c
    cp FULL_ROTATION_DEGREES/4
    jr nc, L8c20
    inc d
    jr L8c36
L8c20:
    cp FULL_ROTATION_DEGREES/2
    jr nc, L8c28
    ld a, 5
    jr L8c2e
L8c28:
    cp 3*FULL_ROTATION_DEGREES/4
    jr nc, L8c36
    ld a, 4
L8c2e:
    add a, d
    cp 9
    jr c, L8c35
    sub 8
L8c35:
    ld d, a
L8c36:
    ; Here:
    ; - d has some number based on the quadrants of pitch/yaw
    ; - these are used to set the limits:
    ;   - in the x/z axis, the maximum limits are [0, 127]
    ;   - in the y axis it is [0, 63]
    ; - all limits that are not set will be replaced by player coordinates.
    dec d
    jr nz, L8c3f
    ; d == 1: yaw 1st quadrant, pitch 4th quadrant:
    ld (ix), 127
    jr L8c83
L8c3f:
    dec d
    jr nz, L8c48
    ; d == 2: yaw 1st quadrant, pitch 1st quadrant:
    ld (ix), 127
    jr L8c8d
L8c48:
    dec d
    jr nz, L8c55
    ; d == 3: yaw 2nd quadrant, pitch 4th quadrant:
    ld (ix), 127
    ld (ix + 2), 63
    jr L8c76
L8c55:
    dec d
    jr nz, L8c5e
    ; d == 4: yaw 2nd quadrant, pitch 1st quadrant:
    ld (ix), 127
    jr L8c72
L8c5e:
    dec d
    jr nz, L8c6b
    ; d == 5: yaw 1st quadrant, pitch 4th quadrant, or
    ;         yaw 2nd quadrant, pitch 1st quadrant
    ld (ix + 1), 0
    ld (ix + 2), 63
    jr L8c76
L8c6b:
    dec d
    jr nz, L8c7c
    ; d == 6: ...
    ld (ix + 1), 0
L8c72:
    ld (ix + 3), 0
L8c76:
    ld (ix + 5), 0
    jr L8c95
L8c7c:
    dec d
    jr nz, L8c89
    ; d == 7: ...
    ld (ix + 1), 0
L8c83:
    ld (ix + 2), 63
    jr L8c91
L8c89:
    ; d == 8: ...
    ld (ix + 1), 0
L8c8d:
    ld (ix + 3), 0
L8c91:
    ld (ix + 4), 127
L8c95:
    dec h
    jp nz, L8bcc_angle_loop

    ; Replace any of the coordinates we have not set above,
    ; with the player x, y, or z coordinates:
    ; These correspond to areas that are "behind" the player, and
    ; hence we use the player coordinates to prune.
    ld hl, (L6aad_player_current_x)
    add hl, hl
    add hl, hl
    ld a, 255
    cp (ix)
    jr nz, L8cab
    inc h
    ld (ix), h
    jr L8cb3
L8cab:
    cp (ix + 1)
    jr nz, L8cb3
    ld (ix + 1), h
L8cb3:
    ld hl, (L6aaf_player_current_y)
    add hl, hl
    add hl, hl
    cp (ix + 2)
    jr nz, L8cc3
    inc h
    ld (ix + 2), h
    jr L8ccb
L8cc3:
    cp (ix + 3)
    jr nz, L8ccb
    ld (ix + 3), h
L8ccb:
    ld hl, (L6ab1_player_current_z)
    add hl, hl
    add hl, hl
    cp (ix + 4)
    jr nz, L8cdb
    inc h
    ld (ix + 4), h
    jr L8ce3
L8cdb:
    cp (ix + 5)
    jr nz, L8ce3
    ld (ix + 5), h
L8ce3:
    ret


; --------------------------------
; Auxiliary variables for L8cf0_project_object_and_add_to_render_list_clipping_internal
L8ce4_projected_data_current_ptr_tmp:  ; Temporary storage of the current vertex data ptr.
    dw #0000
L8ce6_current_face_texture_ID:
    db #00
L8ce7_current_face_normal_check_result:  ; Caches the result of the normal check for the current face
    db #00
L8ce8_screen_corner_coordinates:  ; Used to insert new vertices when clipping.
    db SCREEN_WIDTH_IN_PIXELS, SCREEN_HEIGHT_IN_PIXELS
    db #00, SCREEN_HEIGHT_IN_PIXELS
    db #00, #00
    db SCREEN_WIDTH_IN_PIXELS, #00


; --------------------------------
; Projects an object, and if it falls within the screen, add it to the list of objects to draw,
; assuming that we will have to clip some of the edges as some vertices are outside the viewing area.
; Input:
; - iy: face definition ptr:
;   - first byte is number of faces
;   - then, each face has:
;     - attribute
;     - number of vertices
;     - then one byte per vertex (index)
L8cf0_project_object_and_add_to_render_list_clipping_internal:
    ld hl, (L5f24_shape_edges_ptr)
    ld b, (hl)  ; number of edges
    ; Initialize the L5ee8_already_projected_vertex_coordinates array:
    ; (5 bytes per edge):
    ;   - 0 if not processed, 1 if processed
    ;   - projected x (vertex 1)
    ;   - projected y (vertex 1)
    ;   - projected x (vertex 2)
    ;   - projected y (vertex 2)
    ld hl, L5ee8_already_projected_vertex_coordinates
    ld a, #ff
    ld c, 0
L8cfb:
    ld (hl), c
    inc hl
    ld (hl), a
    inc hl
    inc hl
    ld (hl), a
    inc hl
    inc hl
    djnz L8cfb

    xor a
    ld (L5e5f_add_to_projected_objects_flag), a
    ld hl, (L7497_next_projected_vertex_ptr)
    ld a, (L7468_focus_object_id)
    ; Start writing the projected vertex data:
    ld (hl), a  ; object ID
    inc hl
    ld (hl), 0  ; number of primitives (init to zero, and will be incremented each time a face is added).
    inc hl
    ld b, (iy)  ; number of faces
    inc iy
L8d19_face_loop:
    push bc
        ld a, (iy)  ; a = texture ID.
        inc iy
        ld b, (iy)  ; b = number of vertexes/edges in the face.
        inc iy
        ; If it's a transparent face, ignore:
        or a
        jr z, L8d90_skip_face_bytes_and_next_face
        sla a
        sla a
        sla a
        sla a
        ld c, a  ; c = texture ID (in the most significant nibble).
        ; This first loop goes over the edges looking to see if any vertex passed all the
        ; frustum checks:
        push iy
        push hl
        push bc
            ld a, 1
            ld (L5f28_cull_face_when_no_projected_vertices), a
            ld c, #1e  ; "c" will accumulate the frustum checks of all the vertexes
            inc b
            srl b  ; b = (number of vertexes + 1) * 2
            ld d, 0
L8d40_edge_loop:
            ld a, (iy)  ; vertex/edge index
            and #7f  ; get the index (remove a potential flag in the msb)
            sla a
            ld e, a
            ld ix, (L5f24_shape_edges_ptr)
            inc ix  ; skip the number of vertexes
            add ix, de  ; ix = ptr to the edge
            ld e, (ix)  ; vertex index 1
            ld hl, L5edc_vertex_rendering_frustum_checks
            add hl, de
            ld a, (hl)
            cp #1f
            jr z, L8d76
            ; vertex outside of view frustum:
            and c
            ld c, a
            ld e, (ix + 1)  ; vertex index 2
            ld hl, L5edc_vertex_rendering_frustum_checks
            add hl, de
            ld a, (hl)
            cp #1f
            jr z, L8d76
            ; vertex outside of view frustum:
            and c
            ld c, a
            inc iy
            inc iy
            djnz L8d40_edge_loop

            ld c, a  ; OPTIMIZATION: useless instruction "ld c, a" was just executed above.
            or a
            jr z, L8d7a
L8d76:
            ; We get here if one vertex has passed all frustum tests,
            ; or if the frustum test accumulator (c) is non zero.
            xor a
            ld (L5f28_cull_face_when_no_projected_vertices), a
L8d7a:
        pop bc  ; restore c: texture ID, b: number of edges of face
        pop hl  ; restore hl: ptr to projected vertex data
        pop iy  ; restore iy: face edge data ptr.

        ld a, (L5e60_projection_pre_work_type)
        ;   - if a == 0: indicates that vertices can be projected directly.
        ;   - if a == 1: we need to call L88d1_normal_direction_check before projection, and if back-face, we cull
        ;   - if a == 2: we need to call L88d1_normal_direction_check before projection, and if back-face we need to use L5f26_alternative_shape_edges_ptr        
        or a
        jr z, L8dc7_ready_to_project
        cp 1
        jr nz, L8d98

        ; Normal check, and cull if failed:
        call L88d1_normal_direction_check
        ld (L8ce7_current_face_normal_check_result), a
        jr nc, L8dc7_ready_to_project
L8d90_skip_face_bytes_and_next_face:
        ld c, b
        ld b, 0
        add iy, bc
        jp L8f9f_next_face

L8d98:
        ; Normal check, and use back texture if failed:
        call L88d1_normal_direction_check
        ld (L8ce7_current_face_normal_check_result), a
        ld a, (L746a_current_drawing_texture_id)
        jr nc, L8dba_front_face
        ; back face, we need to swap texture ID, and use alternative shape edges ptr:
        and #f0
        jr z, L8d90_skip_face_bytes_and_next_face
        ld c, a
        ld de, (L5f26_alternative_shape_edges_ptr)
        ld (L5f24_shape_edges_ptr), de
        ; OPTIMIZATION: at this point (L8ce7_current_face_normal_check_result) always contains a 1, so no need to read it and xor, just set to 0.
        ld a, (L8ce7_current_face_normal_check_result)
        xor 1
        ld (L8ce7_current_face_normal_check_result), a
        jr L8dc7_ready_to_project

L8dba_front_face:
        ; Get the texture ID into the most significant nibble of c
        and #0f
        jr z, L8d90_skip_face_bytes_and_next_face
        sla a
        sla a
        sla a
        sla a
        ld c, a

L8dc7_ready_to_project:
        ; At this point:
        ; c = texture ID (most significant nibble)
        ; b = number of edges in the face
        ; hl = ptr to projected vertex data
        ; iy = face edge data ptr.
        ld a, c
        ld (L8ce6_current_face_texture_ID), a
        ld a, b
        cp 2
        jr nz, L8dd1
        dec b  ; If the number of edges is 2, make it 1 (a line).
L8dd1:
        ; This second edge loop: projects all the vertices, clipping them if necessary.
        push iy
        push hl
        push bc
            ld d, 0
L8dd7_edge_loop_2:
            push bc
                ld a, (iy)  ; edge index
                inc iy
                push iy
                    and #7f  ; get rid of the edge flip flag.
                    ld e, a
                    sla a
                    ld c, a  ; c = edge index * 2
                    sla a
                    add a, e
                    ld e, a  ; e = edge index * 5
                    ; Check if this edge had already been processed:
                    ld ix, L5ee8_already_projected_vertex_coordinates
                    add ix, de
                    xor a
                    cp (ix)
                    jr nz, L8e5c_next_edge
                    inc ix
                    ld hl, (L5f24_shape_edges_ptr)
                    inc hl
                    ld e, c
                    add hl, de  ; ptr to the edge
                    ld e, (hl)  ; first vertex of the edge
                    ld iy, L5edc_vertex_rendering_frustum_checks
                    add iy, de
                    ld a, (iy)  ; frustum checks for first vertex of the edge
                    ld c, a
                    cp #1f
                    jr nz, L8e16_second_vertex
                    ; Vertex passed all frustum checks:
                    ld a, (ix)  ; Check if we have already projected it
                    cp #ff
                    jr nz, L8e16_second_vertex
                    ; We need to project it:
                    call L8fa5_project_one_vertex_for_clipping_projection
L8e16_second_vertex:
                    inc hl
                    ld e, (hl)  ; second vertex of the edge
                    dec hl
                    ld iy, L5edc_vertex_rendering_frustum_checks
                    add iy, de
                    ld a, (iy)  ; frustum checks for second vertex of the edge
                    ld b, a
                    cp #1f
                    jr nz, L8e31
                    ld a, (ix + 2)  ; second vertex x
                    cp #ff
                    jr nz, L8e31
                    call L8fa5_project_one_vertex_for_clipping_projection
L8e31:
                    ; Here c and b contain the frustum checks of the two vertices:
                    ld a, b
                    and c
                    cp #1f
                    jr nz, L8e3c_at_least_one_vertex_outside
L8e37:
                    ; If both vertices were within the viewable area, or both outside
                    ; mark this edge as processed:
                    inc (ix - 1)  ; mark the eedge as processed
                    jr L8e5c_next_edge
L8e3c_at_least_one_vertex_outside:
                    ; At least one vertex was outside the view frustum, we need to clip:
                    ld a, b
                    or c
                    cp #1f
                    jr nz, L8e37  ; both vertexes were outside, mark as processed too.
                    ; One vertex was in, the other was out:
                    sla e
                    ld iy, L5e9f_3d_vertex_coordinates_after_rotation_matrix
                    add iy, de
                    add iy, de
                    add iy, de  ; iy = ptr to 3d vertex 2
                    ld e, (hl)  ; get the vertex 1 index again
                    sla e
                    ld hl, L5e9f_3d_vertex_coordinates_after_rotation_matrix
                    add hl, de
                    add hl, de
                    add hl, de  ; hl = ptr to 3d vertex 1
                    call L85ae_clip_edge
                    ld d, 0
L8e5c_next_edge:
                pop iy
            pop bc
            dec b
            jp nz, L8dd7_edge_loop_2
        pop bc
        pop hl
        pop iy

        ; At this point:
        ; b = number of edges in the face
        ; hl = ptr to projected vertex data we are writing to
        ; iy = face edge data ptr.

        ; This third loop adds projected vertices to the projected data, inserting connecting points if necessary.
        ld c, d  ; c = 0 (number of vertices added)
        ld (L8ce4_projected_data_current_ptr_tmp), hl  ; Save the current pointer to the projected vertex data we are writing to
        inc hl
        push bc
L8e6d_edge_loop_3:
            ld a, (iy)  ; edge index
            and #7f  ; get rid of the edge flip flag.
            ld e, a
            sla a
            sla a
            add a, e  ; e = edge index * 5
            ld e, a
            ld d, 0
            ld ix, L5ee8_already_projected_vertex_coordinates
            add ix, de
            ; If this edge was not projected, it means it was fully outside of the
            ; view area, just ignore:
            ld a, (ix + 1)
            cp #ff
            jr z, L8ef5_next_edge
            bit 7, (iy)  ; Check edge flip flag
            jr z, L8ea7_vertices_in_the_correct_order
            ; Flip the projected vertex info:
            ld e, (ix + 1)
            ld d, (ix + 3)
            ld a, d  ; overwrite a with the x projection of the new first vertex.
            ld (ix + 1), d
            ld (ix + 3), e
            ld e, (ix + 2)
            ld d, (ix + 4)
            ld (ix + 2), d
            ld (ix + 4), e
L8ea7_vertices_in_the_correct_order:
            ld e, a  ; vertex 1 x
            ld d, (ix + 2)  ; vertex 1 y
            ld a, c
            or a
            jr z, L8ebe  ; If it's the first vertex we project, skip
            ; Check if the coordinates of vertex 1 are the same as the last projected vertex.
            ; These should match if there was no clipping, but when there is clipping, we might
            ; need to insert additional edges to connect clipped points:
            ld a, e
            dec hl
            dec hl
            cp (hl)  ; compare x coordiantes
            inc hl
            jr nz, L8eb8  ; no x match
            ld a, d
            cp (hl)  ; compare y coordinates
L8eb8:
            inc hl
            jr z, L8ec3_skip_vertex1_insertion
            call L8fea_add_connecting_projected_vertices
L8ebe:
            ; Add vertex to projection and increment vertex count ("c"):
            ld (hl), e
            inc hl
            ld (hl), d
            inc hl
            inc c
L8ec3_skip_vertex1_insertion:
            ld a, (ix + 4)  ; vertex 2 y
            cp d
            ld a, (ix + 3)  ; vertex 2 x
            jr nz, L8ecf
            cp e
            jr z, L8ed7
L8ecf:
            ; Vertex 2 is different from vertex 1:
            ld (hl), a  ; x coordinate
            inc hl
            ld a, (ix + 4)  ; y coordinate
            ld (hl), a
            inc hl
            inc c  ; incremenr number of projected vertices
L8ed7:
            ; If we had flipped the vertices, put them back in their original order:
            bit 7, (iy)
            jr z, L8ef5_next_edge
            ld e, (ix + 1)
            ld d, (ix + 3)
            ld (ix + 1), d
            ld (ix + 3), e
            ld e, (ix + 2)
            ld d, (ix + 4)
            ld (ix + 2), d
            ld (ix + 4), e
L8ef5_next_edge:
            inc iy
            dec b
            jp nz, L8e6d_edge_loop_3

            ld a, c
        pop bc  ; restore the number of edges in b
        ld ix, (L8ce4_projected_data_current_ptr_tmp)
        ld c, a  ; number of projected vertices
        cp 2
        jr nc, L8f69_2_or_more_vertices_projected
        cp 1
        jr nz, L8f0c_0_vertices_projected
        dec hl
        dec hl

L8f0c_0_vertices_projected:
        ld a, b
        cp 1
        jr z, L8f17_discard_current_face
        ld a, (L5f28_cull_face_when_no_projected_vertices)
        or a
        jr nz, L8f1d
L8f17_discard_current_face:
        ; Ignore this face and all projected points so far
        ld hl, (L8ce4_projected_data_current_ptr_tmp)
        jp L8f9f_next_face

L8f1d:
        ld a, (L5e60_projection_pre_work_type)
        or a
        jr nz, L8f3b_we_already_did_normal_check
        ; When L5e60_projection_pre_work_type is zero, we had not done a normal check,
        ; and hence "L5f28_cull_face_when_no_projected_vertices" might not be fully populated,
        ; do it now:
        push iy
            ld a, b
            neg
            ld e, a
            ld d, 255
            add iy, de  ; iy -= number of edes of the face (to reset to the beginning of this face data)
            call L88d1_normal_direction_check
        pop iy
        ld (L8ce7_current_face_normal_check_result), a
        ld a, (L5f28_cull_face_when_no_projected_vertices)
        or a
        jr z, L8f17_discard_current_face

L8f3b_we_already_did_normal_check:
        call L9068_face_covers_whole_screen_check
        ld a, (L5f28_cull_face_when_no_projected_vertices)
        or a
        jr z, L8f17_discard_current_face

        ; Object occupies the whole screen, set screen coordinates as the projected vertices:
        ld de, L8ce8_screen_corner_coordinates
        ex de, hl
        ld bc, 8
        ldir
        ld a, (L8ce6_current_face_texture_ID)
        or 4
        ld (ix), a
        ; Mark that we have objects covering the whols screen:
        ld hl, L7481_n_objects_covering_the_whole_screen
        inc (hl)
        ld hl, (L7497_next_projected_vertex_ptr)
        inc hl
        inc (hl)
        set 7, (hl)
        ex de, hl
        ld a, 1
        ld (L5e5f_add_to_projected_objects_flag), a
    pop bc
    jr L8fa4_ret

L8f69_2_or_more_vertices_projected:
        cp 2
        jr nz, L8f72_close_shape
        ; If we projected just 2 vertices:
        ld a, b
        cp 1  ; If the original object was just a line, we are done
        jr z, L8f8c_successful_face_projection
L8f72_close_shape:
        ; Check if the last vertex we added matches the very first vertex,
        ; if it does, remove it. If it does not, check if we need to insert connecting projected vertices:
        ld e, (ix + 1)
        ld d, (ix + 2)
        ld a, e
        dec hl
        dec hl
        cp (hl)
        inc hl
        jr nz, L8f81
        ld a, d
        cp (hl)
L8f81:
        inc hl
        jr nz, L8f89
        ; Match, remove the last vertex:
        dec c
        dec hl
        dec hl
        jr L8f8c_successful_face_projection
L8f89:
        ; No match, check for necessary connecting vertices:
        call L8fea_add_connecting_projected_vertices
L8f8c_successful_face_projection:
        ; Add the texture / # of vertices byte, mark as projected, and move to next face.
        ld a, (L8ce6_current_face_texture_ID)
        or c
        ld (ix), a

        ld a, 1
        ld (L5e5f_add_to_projected_objects_flag), a
        ld ix, (L7497_next_projected_vertex_ptr)
        inc (ix + 1)  ; increment the number of primitives counter
L8f9f_next_face:
    pop bc
    dec b
    jp nz, L8d19_face_loop
L8fa4_ret:
    ret


; --------------------------------
; This method projects the vertex with index 'e', and writes the projected coordinates
; to the L5ee8_already_projected_vertex_coordinates buffer, assuming we are using
; projection method L8cf0_project_object_and_add_to_render_list_clipping_internal.
; Input:
; - e: vertex index.
L8fa5_project_one_vertex_for_clipping_projection:
    push ix
    push hl
    push de
    push bc
        ld a, e  ; a = vertex index
        sla e
        ld ix, L5e9f_3d_vertex_coordinates_after_rotation_matrix
        add ix, de
        add ix, de
        add ix, de  ; get the 3d vertex pointer
        call L90fc_project_one_vertex
        ld hl, (L5f24_shape_edges_ptr)
        ld ix, L5ee8_already_projected_vertex_coordinates + 1
        ld e, b  ; e = projected y
        ld b, (hl)  ; number of edges
        inc hl
        ; This loop goes through the L5ee8_already_projected_vertex_coordinates array,
        ; and writes projected coordinates for all the vertices that match the current vertex
        ; we just projected.
L8fc4_write_projected_vertex_to_buffer:
        cp (hl)  ; is this the right vertex?
        jr nz, L8fcd
        ; Yes, write projection data!
        ld (ix), c  ; projected x
        ld (ix + 1), e  ; projected y
L8fcd:
        inc ix
        inc ix
        inc hl
        cp (hl)  ; is this the right vertex?
        jr nz, L8fdb
        ; Yes, write projection data!
        ld (ix), c  ; projected x
        ld (ix + 1), e  ; projected y
L8fdb:
        inc ix
        inc ix
        inc ix
        inc hl
        djnz L8fc4_write_projected_vertex_to_buffer
    pop bc
    pop de
    pop hl
    pop ix
    ret


; --------------------------------
; Checks if we need to insert additional projected vertices along the screen edges to
; connect the previous projected vertex with the new one we want to add.
; Input:
; - c: number of inserted vertexes so far
; - e: new vertex projected x
; - d: new vertex projected y
; - hl: ptr to projected vertex data we are writing to
; Output:
; - c: updated number of inserted vertexes so far
; - hl: updated ptr to projected vertex data we are writing to
L8fea_add_connecting_projected_vertices:
    push ix
    push iy
        push hl
        pop ix
        ld hl, 1
        ld a, SCREEN_HEIGHT_IN_PIXELS
        cp (ix - 1)  ; is previous vertex y at the top of the screen?
        jr z, L9009
        inc l  ; l = 2
        xor a
        cp (ix - 2)  ; is previous vertex x in the left of the screen?
        jr z, L9009
        inc l  ; l = 3
        cp (ix - 1)  ; is previous vertex y in the bottom of the screen?
        jr z, L9009
        ld l, a  ; l = 0
L9009:
        ; At this point:
        ; - l = 0: previous vertex at right side of screen
        ; - l = 1: previous vertex at top of screen
        ; - l = 2: previous vertex at left side of screen
        ; - l = 3: previous vertex at bottom of screen
        ld a, SCREEN_WIDTH_IN_PIXELS
        cp e
        jr z, L901a
        inc h
        ld a, SCREEN_HEIGHT_IN_PIXELS
        cp d
        jr z, L901a
        inc h
        xor a
        cp e
        jr z, L901a
        inc h
L901a:
        ; At this point:
        ; - h = 0: new vertex at right side of screen
        ; - h = 1: new vertex at top of screen
        ; - h = 2: new vertex at left side of screen
        ; - h = 3: new vertex at bottom of screen
        ld a, h
        cp l
        jr z, L9060_done  ; both vertexes are in the same side of the screen, we can just insert the new vertex.
        ; Previous and new vertex are not on the same edges of the screen, we need to insert an auxiliary vertex:
        push de
L901f:
            ; Get the coordinates of the screen corner that would help us come closer to
            ; the edge of the new projected vertex:
            ld e, l
            ld d, 0
            sla e
            ld iy, L8ce8_screen_corner_coordinates
            add iy, de
            ld a, (iy)
            ld d, (iy + 1)
            ; Check that we are not adding a point that is identical to the previous one, just in case:
            ld e, a
            cp (ix - 2)
            jr nz, L903c
            ld a, d
            cp (ix - 1)
            jr z, L9057
L903c:
            ; Check that it is not identical to the very first vertex of the face:
            ld iy, (L8ce4_projected_data_current_ptr_tmp)
            ld a, e
            cp (iy + 1)
            jr nz, L904c
            ld a, d
            cp (iy + 2)
            jr z, L9057
L904c:
            ; Insert a new projected vertex:
            ld (ix), e  ; x
            ld (ix + 1), d  ; y
            inc ix
            inc ix
            inc c  ; increase number of projected vertices count.
L9057:
              ; update the screen edge the new previous vertex is at
            inc l
            ld a, l
            and #03
            ld l, a
            ; Have we brought it to the same edge as the new vertex? if so, we are done.
            cp h
            jr nz, L901f
        pop de
L9060_done:
        push ix
        pop hl
    pop iy
    pop ix
    ret


; --------------------------------
; Checks a face that has resulted in no projected vertices covers the whole screen.
; Note: I am not sure about how the math in this function works, as I have not tried to derive the
;       interpretration of he calculations. So, I have named this function based on the effect that
;       it later has when called.
; Input:
; - b: number of edges of face
; - e: number of edges in current face
; - iy: face edge data (pointing to the end of the data)
L9068_face_covers_whole_screen_check:
    push ix
    push iy
    push hl
        xor a
        ld (L5f28_cull_face_when_no_projected_vertices), a
        ld a, b
        neg
        ld e, a
        ld d, 255
        add iy, de  ; iy -= number of edes of the face (to reset to the beginning of this face data)
L9079:
        push bc
            ld a, (iy)
            and #7f
            ld e, a
            ld d, 0
            ld h, d
            sla e
            ld ix, (L5f24_shape_edges_ptr)
            inc ix
            add ix, de
            ld l, (ix)
            ld e, (ix + 1)
            bit 7, (iy)  ; vertex flip flag
            jr z, L909a
            ex de, hl
L909a:
            push iy
                sla e
                ld ix, L5e9f_3d_vertex_coordinates_after_rotation_matrix
                add ix, de
                sla e
                add ix, de  ; ix += vertex 1 index * 6
                ex de, hl
                sla e
                ld iy, L5e9f_3d_vertex_coordinates_after_rotation_matrix
                add iy, de
                sla e
                add iy, de  ; iy += vertex 1 index * 6
                ld e, (ix + 2)
                ld d, (ix + 3)  ; de = vertex 1 y
                ld l, (iy)
                ld h, (iy + 1)  ; hl = vertex 2 x
                call La15e_de_times_hl_signed  ; (de, hl) = vertex 1 y * vertex 2 x
                push de
                    push hl
                        ld e, (ix)
                        ld d, (ix + 1)  ; de = vertex 1 x
                        ld l, (iy + 2)
                        ld h, (iy + 3)  ; hl = vertex 2 y
                        call La15e_de_times_hl_signed  ; (de, hl) = vertex 1 x * vertex 2 y
                    pop bc
                    or a
                    sbc hl, bc  ; (low word) hl = (vertex 1 x * vertex 2 y) - (vertex 1 y * vertex 2 x) (this is done only to get the carry flag for the next operation)
                pop bc
                ex de, hl
                sbc hl, bc    ; (high word) hl = (vertex 1 x * vertex 2 y) - (vertex 1 y * vertex 2 x)
                ld l, 1
                jp p, L90e4
                ld l, 0
L90e4:
            pop iy
        pop bc
        ld a, (L8ce7_current_face_normal_check_result)
        cp l
        jr nz, L90f6
        inc iy
        djnz L9079
        ; Face covers the whole screen!
        ld a, 1
        ld (L5f28_cull_face_when_no_projected_vertices), a
L90f6:
    pop hl
    pop iy
    pop ix
    ret


; --------------------------------
; Projects one vertex from 3d camera coordinates to screen coordinates.
; Input:
; - ix: pointer to a 3d vertex, already transformed, relative to camera view (16 bits per coordinate).
; Output:
; - bc: projected coordinates (c, b) = (x, y)
L90fc_project_one_vertex:
    push hl
    push de
    push af
        ld d, (ix + 5)
        ld e, (ix + 4)  ; de = z
        ld a, e
        or d
        jr nz, L910e_project_x
        ; If z = 0, just project to the center of the screen.
        ld bc, #3860  ; (96, 56)  (center of the screen).
        jr L9170_return
L910e_project_x:
        ld h, (ix + 1)
        ld l, (ix)  ; hl = x
        bit 7, h
        jr z, L9122
        ; x is negative:
        add hl, de
        dec hl    ; hl = x + z - 1
        bit 7, h
        jr z, L912c
        ; x + z - 1 is negative
        ld c, 0  ; screen x = 0
        jr L9140_project_y
L9122:
        or a
        sbc hl, de  ; hl = x - z
        jp m, L912c
        ; x - z is negative
        ld c, SCREEN_WIDTH_IN_PIXELS  ; screen x = 192
        jr L9140_project_y
L912c:
        ld a, SCREEN_WIDTH_IN_PIXELS / 2
        ld h, (ix + 1)
        ld l, (ix)  ; hl = x
        push de
            ; OPTIMIZATION: multiplication by 96 can be accelerated with a custom routine.
            ; (a, hl) = 96 * x
            call La108_a_times_hl_signed  
            ; (a, hl) = 96 * x / z
            call La1cc_a_hl_divided_by_de_signed
        pop de
        ld a, SCREEN_WIDTH_IN_PIXELS / 2
        add a, l
        ld c, a  ; screen x = 96 * x / z + 96
L9140_project_y:
        ld h, (ix + 3)
        ld l, (ix + 2)  ; hl = y
        bit 7, h
        jr z, L9154
        ; y is negative:
        add hl, de
        dec hl  ; hl = y + z - 1
        bit 7, h
        jr z, L915e
        ; y + z - 1 is negative
        ld b, 0  ; screen y = 0
        jr L9170_return
L9154:
        or a
        sbc hl, de  ; hl = y - z
        jp m, L915e
        ; y - z is negative:
        ld b, SCREEN_HEIGHT_IN_PIXELS  ; screen y = 112  
        jr L9170_return
L915e:
        ld a, SCREEN_HEIGHT_IN_PIXELS / 2
        ld h, (ix + 3)
        ld l, (ix + 2)  ; hl = y
        ; OPTIMIZATION: multiplication by 96 can be accelerated with a custom routine.
        ; (a, hl) = 96 * y
        call La108_a_times_hl_signed
        ; (a, hl) = 96 * y / z
        call La1cc_a_hl_divided_by_de_signed
        ld a, SCREEN_HEIGHT_IN_PIXELS / 2
        add a, l
        ld b, a  ; screen x = 56 * x / z + 56
L9170_return:
    pop af
    pop de
    pop hl
    ret


; --------------------------------
; Auxiliary variables for L9177_rotate_relative_bounding_box
L9174_24bit_accumulator:
    db #00, #00, #00


; --------------------------------
; This method does two things:
; - Applies the rotation matrix to the first coordinate in (L7499_3d_object_bounding_box_relative_to_player_ptr),
;   saving it to (L5e9f_3d_vertex_coordinates_after_rotation_matrix).
; - It then multiplies the width, height, length of the object by each row of the
;   rotation matrix, and stores the 9 resulting values in (L5e63_3d_vertex_coordinates_relative_to_player).
; - This method is used for generating vertices for cubes and rectangle objects.
L9177_rotate_relative_bounding_box:
    ld iy, (L7499_3d_object_bounding_box_relative_to_player_ptr)  ; These are in 16bit precision.
    ld ix, L5e55_rotation_matrix
    ld hl, L5e9f_3d_vertex_coordinates_after_rotation_matrix
    ld b, 3
    ; Apply the rotation matrix to the first coordinate in the bounding box, and
    ; save it in L5e9f_3d_vertex_coordinates_after_rotation_matrix
L9184_matrix_coordinate_loop:
    push hl
        ; Multiply the bounding box coordinate 1 by one column of the rotation matrix:
        xor a
        ld (L9174_24bit_accumulator), a
        ld (L9174_24bit_accumulator + 1), a
        ld (L9174_24bit_accumulator + 2), a
        ld a, (ix)  ; get the rotation matrix element
        inc ix
        or a
        jr z, L91a6_matrix_cell_is_zero
        ; L9174_24bit_accumulator = bounding box x * matrix[b][0]
        ld l, (iy)
        ld h, (iy + 1)
        call La108_a_times_hl_signed
        ld (L9174_24bit_accumulator + 2), a
        ld (L9174_24bit_accumulator), hl
L91a6_matrix_cell_is_zero:
        ld a, (ix)  ; get the next rotation matrix element
        inc ix
        or a
        jr z, L91c7_matrix_cell_is_zero
        ; L9174_24bit_accumulator += bounding box z * matrix[b][1]
        ld l, (iy + 4)
        ld h, (iy + 5)
        call La108_a_times_hl_signed
        ld de, (L9174_24bit_accumulator)
        add hl, de
        ld (L9174_24bit_accumulator), hl
        ld e, a
        ld a, (L9174_24bit_accumulator + 2)
        adc a, e
        ld (L9174_24bit_accumulator + 2), a
L91c7_matrix_cell_is_zero:
        ld a, (ix)  ; get the next rotation matrix element
        inc ix
        or a
        jr z, L91e8_matrix_cell_is_zero
        ; L9174_24bit_accumulator += bounding box y * matrix[b][2]
        ld l, (iy + 8)
        ld h, (iy + 9)
        call La108_a_times_hl_signed
        ld de, (L9174_24bit_accumulator)
        add hl, de
        ld (L9174_24bit_accumulator), hl
        ld e, a
        ld a, (L9174_24bit_accumulator + 2)
        adc a, e
        ld (L9174_24bit_accumulator + 2), a
L91e8_matrix_cell_is_zero:
        ld hl, (L9174_24bit_accumulator)
        ld a, (L9174_24bit_accumulator + 2)
        add hl, hl
        rla
        add hl, hl
        rla
        ld e, h  ; (a, e) = (a, hl) / 64
    pop hl
    ld (hl), e
    inc hl
    ld (hl), a
    inc hl
    djnz L9184_matrix_coordinate_loop

    ; Calculate the 9 terms resulting from multiplying (width, height, length) of the object by
    ; each row of the rotation matrix, and store them in L5e63_3d_vertex_coordinates_relative_to_player (16 bit precision).
    ld hl, (L749d_object_currently_being_processed_ptr)
    ld de, 4
    add hl, de
    ex de, hl  ; de = points to the (width, height, length) of the object
    ld ix, L5e55_rotation_matrix
    ld iy, L5e63_3d_vertex_coordinates_relative_to_player
    ld b, 3
    ; 3 iterations, one for width, onr for height, one for length:
L920c_coordinate_loop:
    ld a, (de)  ; get the w, h or l
    inc de
    ; Multiply by the first row element:
    ld l, (ix)
    ld h, a
    call La253_h_times_l_signed
    ld (iy), l
    ld (iy + 1), h
    inc iy
    inc iy
    ; Multiply by the second row element:
    ld l, (ix + 3)
    ld h, a
    call La253_h_times_l_signed
    ld (iy), l
    ld (iy + 1), h
    inc iy
    inc iy
    ; Multiply by the third row element:
    ld l, (ix + 6)
    ld h, a
    call La253_h_times_l_signed
    ld (iy), l
    ld (iy + 1), h
    inc iy
    inc iy
    inc ix  ; move to next row of the matrix
    djnz L920c_coordinate_loop
    ret


; --------------------------------
; Checks if vertices of an object fall inside of the rendering frustum.
;
; Note: in modern 3d engines, the rendering volume is a frustum, but in
; this engine, this is simplified and they use a pyramid. We could easily
; turn it to a frustum, changing the 5th test to be a bit a head of the
; player, rather than exactly at the player. I am still calling it "frustum"
; for clarity (for those familiar with modern engines).
; Input:
; - a: number of vertices.
; Returns:
; - z: object is visible, nz: object is not visible.
; - updates (L5e5e_at_least_one_vertex_outside_rendering_frustum)
L9246_object_visibility_check:
    ld (L7496_current_drawing_primitive_n_vertices), a
    ld iy, L5e9f_3d_vertex_coordinates_after_rotation_matrix
    ld de, L5edc_vertex_rendering_frustum_checks
    ld b, a
    xor a
    ld (L5e5e_at_least_one_vertex_outside_rendering_frustum), a
    ld c, a
L9256_vertex_loop:
    push bc
        ; This code performs 5 culling checks:
        ; - assuming the rendering volume is a pyramid (with vertex in the player):
        ; - 4 checks for the 4 walls of the pyramid
        ; - a 5th check to see if the object is behind the player
        ; - 'a' is initialized with 5 bits set to 1, indicating the tests pass.
        ; - Each time a test fails (vertex is outside the rendering volume), one bit is set to 0.
        ld a, #1f
        ld c, (iy + 4)  
        ld b, (iy + 5)  ; bc = vertex z
        ld l, (iy)
        ld h, (iy + 1)  ; hl = vertex x
        push hl
            or a
            adc hl, bc  ; hl = x + z
            jp p, L926e_positive
            and #0f  ; zero out bit 4
L926e_positive:
            ld l, (iy + 2)
            ld h, (iy + 3)  ; hl = vertex y
            push hl
                or a
                adc hl, bc  ; hl = y + z
                jp p, L927d_positive
                and #17  ; zero out bit 3
L927d_positive:
            pop hl
            or a
            sbc hl, bc  ; hl = y - z
            jp m, L9286_negative
            and #1d  ; zero out bit 2
L9286_negative:
        pop hl
        or a
        sbc hl, bc  ; hl = x - z
        jp m, L928f_negative
        and #1b  ; zero out bit 1
L928f_negative:
        bit 7, b
        jr z, L9295_z_positive
        ; vertex behind the camera
        and #1e  ; zero out bit 0
L9295_z_positive:
        ld bc, 6
        add iy, bc  ; next vertex
    pop bc
    ld (de), a
    inc de
    cp #1f
    jr z, L92a8
    ; At least one of the culling tests failed (point is outside the view frustum).
    ; Hence, mark that we will use "L8cf0_project_object_and_add_to_render_list_clipping_internal"
    ; instead of "L8adc_project_object_and_add_to_render_list_internal".
    ; OPTIMIZATION: below, better do ld hl,L5e5e_at_least_one_vertex_outside_rendering_frustum; ld (hl),1
    ld h, a  ; save 'a'
    ld a, 1
    ld (L5e5e_at_least_one_vertex_outside_rendering_frustum), a
    ld a, h  ; restore 'a'
L92a8:
    ; - 'c' accumulates the culling checks. 
    ; - 'c' will be #1f if at least one point has passed all the tests, or if collectively,
    ;   each test has been passed by at least one point.
    or c
    ld c, a
    djnz L9256_vertex_loop
    ld a, c
    cp #1f
    ret


; --------------------------------
; Projects an object, and if it falls within the screen, add it to the list of objects to draw.
; Input:
; - a: projection type.
;   - if a == 0: indicates that vertices can be projected directly.
;   - if a == 1: we need to call L88d1_normal_direction_check before projection, and if back-face, we cull
;   - if a == 2: we need to call L88d1_normal_direction_check before projection,  we need to use L5f26_alternative_shape_edges_ptr
; - iy: face definition pointer.
L92b0_project_object_and_add_to_render_list:
    ld (L5e60_projection_pre_work_type), a
    ld a, (L5e5e_at_least_one_vertex_outside_rendering_frustum)
    or a
    jr nz, L92be
    ; Easy case, all vertices within rendering volume:
    call L8adc_project_object_and_add_to_render_list_internal
    jr L92c1_continue
L92be:
    ; Complex case, not all vertices within rendering volume:
    call L8cf0_project_object_and_add_to_render_list_clipping_internal
L92c1_continue:
    ld a, (L5e5f_add_to_projected_objects_flag)
    or a
    jr z, L92eb_do_not_draw
    ; This object has to be drawn, add it to the list of projected objects:
    ld de, (L7497_next_projected_vertex_ptr)  ; Get the ptr we just wrote the object to.
    ld (L7497_next_projected_vertex_ptr), hl  ; Update the ptr for the next object to just after the current one.
    ld hl, (L749b_next_object_projected_data_ptr)
    ; Save the pointer to the projected vertex data for this object:
    ld (hl), e
    inc hl
    ld (hl), d
    inc hl
    ; Save the pointer to the relative bounding box for this object:
    ld de, (L7499_3d_object_bounding_box_relative_to_player_ptr)
    ld (hl), e
    inc hl
    ld (hl), d
    inc hl
    ld (L749b_next_object_projected_data_ptr), hl
    ; hl = de + 12 (next bounding box ptr)
    ld hl, 12
    add hl, de
    ld (L7499_3d_object_bounding_box_relative_to_player_ptr), hl
    ld hl, L746b_n_objects_to_draw
    inc (hl)
L92eb_do_not_draw:
    ret


; --------------------------------
; Draws a primitive (line, or polygon)
; Input:
; - ix: pointer to the primitive data
; - (L7496_current_drawing_primitive_n_vertices): number of vertices of the primitive.
; Output:
; - ix: ptr to the next primitive.
L92ec_draw_primitive:
    push hl
    push de
    push bc
    ex af, af'
    push af
    exx
    push hl
    push de
    push bc
        ld a, (L7496_current_drawing_primitive_n_vertices)
        cp 2
        jp nz, L937d_draw_polygon
        ; Case 1: Draw a line.
        ; Lines are defined by just 4 bytes:
        ld l, (ix)      ; x1
        ld h, (ix + 1)  ; y1
        ld e, (ix + 2)  ; x2
        ld d, (ix + 3)  ; y2
        ld bc, 4
        add ix, bc  ; move ix to the next primitive.
        push ix
            ld a, d
            sub h
            jr nc, L9317_line_drawing_order_set
            neg
            ex de, hl  ; if the line was to be drawn downwards, swap the points
L9317_line_drawing_order_set:
            ld b, a  ; y2 - y1
            ld a, h  ; y1
            ld (L7508_current_drawing_row), a
            call L94c4_calculate_row_ptr_and_texture_ptr
            ld a, b
            or a
            jr nz, L9328_line_is_not_horizontal
            ; It is a horizontal line:
            ld h, l
            ld d, e
            jp L94b5_draw_texture_row_and_return
L9328_line_is_not_horizontal:
            ld c, l  ; starting x pixel
            push bc
                ld a, h
                sub d
                ld c, a
                ld b, #ff  ; bc = y1 - y2
                dec bc
                ld a, l
                sub e  ; a = x1 - x2
                ld de, 0
                ld l, e
                jr nc, L9339
                ; (de, hl) should be negative
                dec de
L9339:
                ld h, a  ; hl = (x1 - x2) * 256
                ; Calculate the line slope:
                ; - slope = dx * 256 / dy
                call Lb1b7_de_hl_divided_by_bc_signed
                ld (L7504_line_drawing_slope), hl
                ld a, 1
                bit 7, d
                jr nz, L9348_thinning_direction_set
                ; If the result is negative, mark that we want to thicken the line
                ; to the left in case the line is to thin to be drawn in any row.
                ld a, -1
L9348_thinning_direction_set:
                ld (L7509_line_drawing_thinning_direction), a
            pop bc
            inc b  ; number of rows to draw
            ; Initialize both points (de and hl) to the beginning of the line (bottom):
            ld h, c  ; c == starting x pixel
            ld l, 0
            ld d, h
            ld e, l
            push bc
                ; Advance one of the two pixels, so they are offset by 1 vertical pixel.
                ld bc, (L7504_line_drawing_slope)
                add hl, bc
                jr L936e_line_draw_entry_point
L935a_line_draw_row_loop:
            ; Line drawing using fixed-point arithmetic:
            ; - Keeps two points (one in the current Y position, and one in the previous), and draws
            ;   horizontal lines at each row to connect them.
            push bc
                ; Draw pixels from 'd' -> 'h'
                call L94fe_draw_texture_row
                ; Mark we are moving to the next row:
                ld a, (L7508_current_drawing_row)
                inc a
                ld (L7508_current_drawing_row), a
                ld bc, (L7504_line_drawing_slope)
                ; Advance both current (hl) and previous (de) points:
                ex de, hl
                add hl, bc
                ld d, h
                ld e, l
                add hl, bc
L936e_line_draw_entry_point:
                ld a, h
                cp d
                jr z, L9377_skip_line_thinning
                ; If 'd != h', move 'h' one pixel in the direction of 'd' to make sure the line is thin when drawn.
                ld a, (L7509_line_drawing_thinning_direction)
                add a, h
                ld h, a
L9377_skip_line_thinning:
            pop bc
            djnz L935a_line_draw_row_loop
            jp L94b5_draw_texture_row_and_return

L937d_draw_polygon:
        ; Case 2: Draw a triangle.
        ld (L750b_current_drawing_n_vertices_left), a
        ; Copy the vertices to a temporary buffer:
        ld c, a
        sla c
        ld b, 0
        push ix
        pop hl
        ld de, L7510_current_drawing_2d_vertex_buffer
        ldir

        ; Make a second copy (so we can iterate to the right without overflowing, starting from any vertex):
        push ix
        pop hl
        ld c, a
        sla c
        ldir

        push hl
            ld hl, L7510_current_drawing_2d_vertex_buffer + 1
            ld d, h
            ld e, l
            ld b, a
            dec b
            ld a, (hl)
L939e_find_lowest_point_loop:
            inc hl
            inc hl
            cp (hl)
            jr c, L93a6_not_lowest
            ; new lowest:
            ld d, h  ; save the pointer
            ld e, l
            ld a, (hl)  ; save the y coordinate
L93a6_not_lowest:
            djnz L939e_find_lowest_point_loop
            dec de  ; point to the x coordinate of the lowest point
            ld (L7508_current_drawing_row), a
            call L94c4_calculate_row_ptr_and_texture_ptr
            push de
            pop ix

            push de
            pop iy
            ld a, (L7496_current_drawing_primitive_n_vertices)
            inc a
            ld c, a
            sla c
            add iy, bc
            dec ix
            dec ix
            ; Here:
            ; - ix: at point to the left of lowest
            ; - iy: at the lowest point in the second copy of the vertices.
            ; During the loop, we will move ix forward and iy backwards
            ; (util they meet, and then we are done).
            ; During the loop, we will have:
            ; - hl: x coordinate of the iy line
            ; - de: x coordinate of the ix line
            ld a, #03
            ; The first time we move in the ix or iy lines, we only move 1/2 a step. The
            ; two lowest bits of (L750a_first_loop_flags) indicate if we have already done this.
            ; As soon as we do the 1/2 step, they are set to 0, to do full steps from that point on.
            ld (L750a_first_loop_flags), a
            ld a, (L7508_current_drawing_row)
            jr L93e2_draw_polygon_loop_entry_point
L93cc_draw_polygon_loop:
            call L94fe_draw_texture_row
            ld bc, (L7504_line_drawing_slope)
            add hl, bc  ; advance the iy line
            ld bc, (L7506_polygon_drawing_second_slope)
            ex de, hl
                add hl, bc  ; advance the ix line
            ex de, hl
            ld a, (L7508_current_drawing_row)
            inc a
            ld (L7508_current_drawing_row), a
L93e2_draw_polygon_loop_entry_point:
            cp (iy - 1)  ; compare the "y" of the next point in iy with the current "y".
            jr nz, L943a  ; we have not yet reached the "y" coordinate of the next point
            ; We have reached the "y" coordinate of the next point, advance iy!:
L93e7_skip_horizontal_iy_points_loop:
            ld a, (L750b_current_drawing_n_vertices_left)
            dec a
            jp m, L9493_draw_polygon_done
            ld (L750b_current_drawing_n_vertices_left), a
            dec iy
            dec iy
            ld a, (iy + 1)
            sub (iy - 1)
            jr z, L93e7_skip_horizontal_iy_points_loop  ; If the next point is also in the same 'y', keep skipping.
            jp nc, L9493_draw_polygon_done  ; If we close the shape, and start moving backwads in 'y', we are done.
            dec a  ; a is negative here, so, we grow it by one
            exx
                ld c, a
                ld b, #ff  ; bc = a (extend sign, as a is negative for sure)
                ld hl, 0
                ld d, h
                ld e, h
                ld a, (iy)  ; x coordinate
                sub (iy - 2)  ; a = difference between next point x and this point's x
                jr z, L9419_slope_calculated
                ld h, a
                jr nc, L9416_de_hl_positive
                dec de  ; make (de, hl) negative
L9416_de_hl_positive:
                ; here: (de, hl) = dx * 256
                ; Calculate the iy line slope:
                ; - slope = dx * 256 / dy
                call Lb1b7_de_hl_divided_by_bc_signed
L9419_slope_calculated:
                ld (L7504_line_drawing_slope), hl
            exx
            ld h, (iy)  ; x coordinate of the iy line
            ld l, 0
            ld bc, (L7504_line_drawing_slope)
            ld a, (L750a_first_loop_flags)
            bit 0, a
            jr nz, L9431_full_step
            ; If the first-loop flag is set, only do half a step:
            sra b  ; bc /= 2
            rr c
L9431_full_step:
            and #fe
            ld (L750a_first_loop_flags), a
            add hl, bc  ; move one step for the "iy" point
            ld a, (L7508_current_drawing_row)
L943a:
            cp (ix + 3)  ; Have we reached the "y" coordinate of the next point in ix?
            jr nz, L93cc_draw_polygon_loop  ; We have not, so, we draw the next row!
L943f_skip_horizontal_ix_points_loop:
            ld a, (L750b_current_drawing_n_vertices_left)
            dec a
            jp m, L9493_draw_polygon_done
            ld (L750b_current_drawing_n_vertices_left), a
            inc ix
            inc ix
            ld a, (ix + 1)
            sub (ix + 3)
            jr z, L943f_skip_horizontal_ix_points_loop  ; If the next point is also in the same 'y', keep skipping.
            jr nc, L9493_draw_polygon_done  ; If we close the shape, and start moving backwads in 'y', we are done.
            dec a
            exx
                ld c, a
                ld b, #ff  ; bc = a (extend sign, as a is negative for sure)
                ld hl, 0
                ld d, h
                ld e, h
                ld a, (ix)  ; x coordinate
                sub (ix + 2)  ; a = difference between next point x and this point's x
                jr z, L9470_slope_calculated
                ld h, a
                jr nc, L946d_de_hl_positive
                dec de  ; make (de, hl) negative
L946d_de_hl_positive:
                ; here: (de, hl) = dx * 256
                ; Calculate the ix line slope:
                ; - slope = dx * 256 / dy
                call Lb1b7_de_hl_divided_by_bc_signed
L9470_slope_calculated:
                ld (L7506_polygon_drawing_second_slope), hl
            exx
            ld d, (ix)  ; x coordinate of the ix line
            ld e, 0
            ld bc, (L7506_polygon_drawing_second_slope)
            ld a, (L750a_first_loop_flags)
            bit 1, a
            jr nz, L9488_full_step
            ; If the first-loop flag is set, only do half a step:
            sra b  ; bc /= 2
            rr c
L9488_full_step:
            and #fd
            ld (L750a_first_loop_flags), a
            ex de, hl
                add hl, bc
            ex de, hl
            jp L93cc_draw_polygon_loop

L9493_draw_polygon_done:
            ; Draw the last row:
            ld a, (L750a_first_loop_flags)
            or a
            jr z, L94b5_draw_texture_row_and_return
            ; We have not moved both lines at least once. This means we are probably just
            ; drawing a tiny polygon. Hence, here we find the lowest 'x' in d, and the largest 
            ; 'x' in e, to draw a line from d to e, so that at least something is visualized.
            ld hl, L7510_current_drawing_2d_vertex_buffer
            ld e, (ix)  ; get current 'x'
            ld d, e  ; min/max 'x' set to the vlaue of the first vertex
            ld a, (L7496_current_drawing_primitive_n_vertices)
            dec a
            ld b, a
L94a5_min_max_vertex_loop:
            inc hl
            inc hl
            ld a, (hl)
            cp e
            jr nc, L94ae_not_larger
            ld e, a  ; new maximum
            jr L94b2_not_smaller
L94ae_not_larger:
            cp d  ; new minimum
            jr c, L94b2_not_smaller
            ld d, a
L94b2_not_smaller:
            djnz L94a5_min_max_vertex_loop
            ld h, e
L94b5_draw_texture_row_and_return:
            call L94fe_draw_texture_row
        pop ix
    pop bc
    pop de
    pop hl
    exx
    pop af
    ex af, af'
    pop bc
    pop de
    pop hl
    ret


; --------------------------------
; Calculates the pointer to row "a", and the texture pointer associated with the
; current object texture.
; Input:
; - a: row (starting from the bottom)
; - (L746a_current_drawing_texture_id): texture ID.
L94c4_calculate_row_ptr_and_texture_ptr:
    push hl
    push de
        ; Calculate the position in the render buffer of row 'a' (starting from the bottom):
        ; (SCREEN_HEIGHT_IN_PIXELS - a)
        sub SCREEN_HEIGHT_IN_PIXELS
        neg
        ld l, a
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        ld d, h
        ld e, l
        add hl, hl
        add hl, de  ; hl = (SCREEN_HEIGHT_IN_PIXELS - a) * SCREEN_WIDTH
        ld de, L5cbc_render_buffer
        add hl, de
        ld (L750c_current_drawing_row_ptr), hl  ; Store the position of the row in L750c_current_drawing_row_ptr
        ; Calculate the texture pattern pointer:
        ld hl, Ld088_texture_patterns  ; Each texture is 4 bytes in size
        ld a, (L746a_current_drawing_texture_id)
        dec a
        ld e, a
        ld d, 0
        sla e
        sla e
        add hl, de  ; hl = Ld088_texture_patterns + 4 * (L746a_current_drawing_texture_id)
        ld (L750e_current_drawing_texture_ptr), hl
    pop de
    pop hl
    ret


; --------------------------------
; Masks:
; - To filter out half of a byte (left half or right half) at various split points.
; - To get the one-hot representation of a given bit.
L94f0_byte_splitting_masks:
    db #80, #c0, #e0, #f0, #f8, #fc, #fe
L94f7_one_hot_pixel_masks:
    db #40, #20, #10, #08, #04, #02, #01


; --------------------------------
; Draws the current texture (L750e_current_drawing_texture_ptr),
; to pixels starting at 'h' and ending before 'd' in row (L7508_current_drawing_row).
; If any of the two extremes (d or h) is ouside of the screen, nothing is drawn.
; Input:
; - h: x1 -> x coordinate of the first pixel to draw.
; - d: x2 -> x coordinate of where to end drawing pixels.
L94fe_draw_texture_row:
    ; Prevent drawing outside of the screen:
    ld a, h
    cp SCREEN_WIDTH_IN_PIXELS + 1
    ret nc
    ld a, d
    cp SCREEN_WIDTH_IN_PIXELS + 1
    ret nc
    push hl
    push de
        ; Get the byte we want to draw. Each texture has 4 bytes, defining
        ; a repeating texture vertically. So, "current row % 4" is the
        ; offset in the current texture we want to use:
        ld a, (L7508_current_drawing_row)
        and #03
        ld c, a
        ld e, h  ; x coordinate to start drawing to (in pixels)
        ld b, 0
        ld hl, (L750e_current_drawing_texture_ptr)
        add hl, bc
        ex af, af'
            ld a, (hl)  ; Save byte we want to write to 'ghost a'.
        ex af, af'
        ld hl, (L750c_current_drawing_row_ptr)
        ld a, d
        sub e  ; a = d - h  number of pixels to draw
        jr nc, L9522
        ; number of pixels to draw is negative, flip it:
        ld e, d
        neg
L9522:
        ; Here:
        ; - a: number of bytes to draw
        ; - e: start x coordinate
        ; - ghost a: byte to draw
        inc a  ; increment 'a', as later the djnz will decrement 'b' (which will hold the value of 'a')
        ld b, a
        xor a
        ld d, a
        cp e
        jr nz, L952e
        ; We start drawing from the left
        djnz L955c_start_ptr_calculated
        ; If there is only 1 pixel to draw in the left-most part of the screen, do not draw it, just skip.
        jp L95bf_advance_ptr_to_next_row_and_return
L952e:
        ; Calculate the pointer where to start drawing:
        dec e
        ld a, e
        srl e
        srl e
        srl e
        add hl, de  ; hl = (L750c_current_drawing_row_ptr) + (start x - 1) / 8
        and #07
        jr z, L955c_start_ptr_calculated
        ; There are some left-over pixels at the beginning (not a full byte), draw them:
        ld e, a
        dec e
        push hl
            ; Get the pointer in to the one_hot mask of the first bit we want to draw
            ld hl, L94f7_one_hot_pixel_masks
            add hl, de
            ld a, 7
            sub e
            ld e, a  ; number of pixels to draw
            xor a
            ; OPTIMIZATION: the loop below is unnecessary, the one_hot_pixel_masks, should just contain the result of the loop below...
L9547_prefix_pixels_mask_loop:
            or (hl)
            inc hl
            dec b
            jr z, L954f_mask_calculated
            dec e
            jr nz, L9547_prefix_pixels_mask_loop
L954f_mask_calculated:
        pop hl
        ; We have calculated the mask corresponding to the first left-over pixels, draw them:
        ld d, a
        cpl
        and (hl)
        ld c, a
        ex af, af'
            ld e, a  ; texture byte to draw
        ex af, af'
        ld a, d
        and e
        or c
        ld (hl), a
        inc hl
L955c_start_ptr_calculated:
        ; Here:
        ; - b: number of pixels to write.
        ; - hl: ptr to where to write them.
        ; - ghost a: byte we want to write.
        ld e, b
        srl e
        srl e
        srl e
        ld d, 0
        add hl, de  ; hl now points to the end of where we want to write.
        ld a, b
        and #07
        ; If the number of pixels to write was a multiple of 8, we are done!
        jr z, L9581_byte_to_write_and_amount_calculated
        ; Number of pixels to write is not a multiple of 8, we need to write 'a' left over pixels:
        exx
            ; Get the mask to mask out the pixels we do not want to modify:
            dec a
            ld c, a
            ld hl, L94f0_byte_splitting_masks
            ld b, 0
            add hl, bc
            ld a, (hl)
        exx
        ; Write only the desired number of bits 'd' over to '(hl)':
        ld b, a
        cpl
        and (hl)  ; keep only the bits we want to preserve from the background
        ld c, a
        ex af, af'
            ld d, a  ; byte we want to write
            and b  ; keep only the bits we want to modify
            or c  ; combine them
            ld (hl), a  ; write to (hl)
            ld a, d  ; restore the byte to write in 'ghost a'
        ex af, af'
L9581_byte_to_write_and_amount_calculated:
        ; Here:
        ; - e: number of bytes to write.
        ; - ghost a: byte to write.
        ; - hl: ptr to the byte after the last byte we need to write.
        ld a, e
        or a
        jr z, L95bf_advance_ptr_to_next_row_and_return
        ex af, af'
            ld e, a  ; Save the byte to write in e
        ex af, af'
        srl a  ; a = number of bytes to write / 2
        jr nc, L958e_even_number_of_bytes_left
        dec hl
        ld (hl), e  ; If the number of bytes to write is odd, write the first byte
L958e_even_number_of_bytes_left:
        jr z, L95bf_advance_ptr_to_next_row_and_return
        cp 5
        jp p, L959e_write_bytes_via_push
        ld b, a
L9596_write_bytes_via_loop:
        ; If there are 10 or less bytes to copy, this is faster:
        dec hl
        ld (hl), e
        dec hl
        ld (hl), e
        djnz L9596_write_bytes_via_loop
        jr L95bf_advance_ptr_to_next_row_and_return
L959e_write_bytes_via_push:
        ; If there are more than 10 bytes to copy, this is faster:
        ; Copy value "e" to "a"*2 bytes starting at (hl-1), and going backwards.
        di
        ld (L7502_sp_tmp), sp
        ld sp, hl
        ld d, e
        ld c, a
        ld hl, L95ba_end_of_pushes
        xor a
        ld b, a
        sbc hl, bc
        jp hl  ; Executes "a" "push de" instructions
        ; There are 12 "push de" instructions here, each of them can copy 2 bytes, so, 12*2 = 24, which is
        ; a whole horizontal row of the screen.
        push de
        push de
        push de
        push de
        push de
        push de
        push de
        push de
        push de
        push de
        push de
        push de
L95ba_end_of_pushes:
        ld sp, (L7502_sp_tmp)
        ei
L95bf_advance_ptr_to_next_row_and_return:
        ld hl, (L750c_current_drawing_row_ptr)
        ld de, -SCREEN_WIDTH
        add hl, de
        ld (L750c_current_drawing_row_ptr), hl
    pop de
    pop hl
    ret


; --------------------------------
; Variables for L95de_init_rotation_matrix
L95cc_identity_matrix:  ; stored in columns - rows
    db #40, #00, #00  ; 1st column
    db #00, #40, #00  ; 2nd column
    db #00, #00, #40  ; 3rd column
L95d5_scaling_matrix:  ; Used after the rotation matrix is calculated, to apply some scaling in the x and z axis.
    db #28, #00, #00
    db #00, #40, #00
    db #00, #00, #20


; --------------------------------
; Computes the rotation matrix (rotation + scale),
; and initializes all the pointers and buffers to start projecting 3d objects into 2d coordinates.
L95de_init_rotation_matrix:
    ; Initialize the yaw rotation matrix to the identity matrix:
    ld bc, 9
    ld hl, L95cc_identity_matrix
    ld de, L5e55_rotation_matrix
    ldir
    ld a, (L6ab7_player_yaw_angle)
    or a
    jr z, L960b_yaw_matrix_computed
    ; Set L5e55_rotation_matrix to be a 3d rotation matrix around the "y" axis:
    ld iy, L73c6_cosine_sine_table
    add a, a
    ld c, a
    add iy, bc
    ld a, (iy + 1)  ; sin(yaw)
    ld (L5e55_rotation_matrix), a
    ld (L5e55_rotation_matrix + 8), a
    ld a, (iy)  ; cos(yaw)
    ld (L5e55_rotation_matrix + 6), a
    neg
    ld (L5e55_rotation_matrix + 2), a
L960b_yaw_matrix_computed:
    ld a, (L6ab6_player_pitch_angle)
    or a
    jr z, L963a_zero_pitch
    ; Initialize the yaw rotation matrix to the identity matrix:
    ld c, 9
    ld hl, L95cc_identity_matrix
    ld de, L5e4c_pitch_rotation_matrix
    ldir
    ; Set L5e4c_pitch_rotation_matrix to be a 3d rotation matrix around the "x" axis:
    ld iy, L73c6_cosine_sine_table
    add a, a
    ld c, a
    add iy, bc
    ld a, (iy + 1)  ; sin(pitch)
    ld (L5e4c_pitch_rotation_matrix + 4), a
    ld (L5e4c_pitch_rotation_matrix + 8), a
    ld a, (iy)  ; cos(pitch)
    ld (L5e4c_pitch_rotation_matrix + 5), a
    neg
    ld (L5e4c_pitch_rotation_matrix + 7), a
    call La089_3x3_matrix_multiply
L963a_zero_pitch:
    ; Multiply the current rotation matrix by a predefined scaling matrix:
    ld c, 9
    ld hl, L95d5_scaling_matrix
    ld de, L5e4c_pitch_rotation_matrix
    ldir
    call La089_3x3_matrix_multiply
    ld hl, L5fa2_3d_object_bounding_boxes_relative_to_player
    ld (L7499_3d_object_bounding_box_relative_to_player_ptr), hl
    ld hl, L67f4_projected_vertex_data
    ld (L7497_next_projected_vertex_ptr), hl
    ld hl, L6754_current_room_object_projected_data
    ld (L749b_next_object_projected_data_ptr), hl
    xor a
    ld (L746b_n_objects_to_draw), a
    ld (L7481_n_objects_covering_the_whole_screen), a
    ret


; --------------------------------
; Projects a cube. Using the object bounding box, generates the 3d vertices for a cube, and
; then calls the projection method for adding them to the render list.
; Called to project objects with type "OBJECT_TYPE_CUBE"
; - When this function is called this has already happened:
;   - rendering cube volume has been calculated
;   - rotation matrix has already been set
;   - cube volume culling check has been done
;   - player_collision_with_object_flags has been set
;   - object bounding box coordinates relative to player have been stored in
;     (L7499_3d_object_bounding_box_relative_to_player_ptr)
L9661_project_cube_objects:
    call L9177_rotate_relative_bounding_box
    ; Calculate the 8 cube vertices, and store them in (L5e9f_3d_vertex_coordinates_after_rotation_matrix):
    ld hl, (L5e9f_3d_vertex_coordinates_after_rotation_matrix)
    ld de, (L5e63_3d_vertex_coordinates_relative_to_player)
    add hl, de
    ld (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 3*2), hl
    ld (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 6*2), hl
    ld (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 15*2), hl
    ld (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 18*2), hl
    ld hl, (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 1*2)
    ld de, (L5e63_3d_vertex_coordinates_relative_to_player + 2)
    add hl, de
    ld (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 4*2), hl
    ld (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 7*2), hl
    ld (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 16*2), hl
    ld (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 19*2), hl
    ld hl, (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 2*2)
    ld de, (L5e63_3d_vertex_coordinates_relative_to_player + 2*2)
    add hl, de
    ld (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 5*2), hl
    ld (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 8*2), hl
    ld (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 17*2), hl
    ld (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 20*2), hl
    ld hl, (L5e9f_3d_vertex_coordinates_after_rotation_matrix)
    ld de, (L5e63_3d_vertex_coordinates_relative_to_player + 3*2)
    add hl, de
    ld (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 9*2), hl
    ld (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 21*2), hl
    ld hl, (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 6*2)
    add hl, de
    ld (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 6*2), hl
    ld hl, (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 18*2)
    add hl, de
    ld (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 18*2), hl
    ld hl, (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 1*2)
    ld de, (L5e63_3d_vertex_coordinates_relative_to_player + 4*2)
    add hl, de
    ld (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 10*2), hl
    ld (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 22*2), hl
    ld hl, (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 7*2)
    add hl, de
    ld (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 7*2), hl
    ld hl, (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 19*2)
    add hl, de
    ld (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 19*2), hl
    ld hl, (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 2*2)
    ld de, (L5e63_3d_vertex_coordinates_relative_to_player + 5*2)
    add hl, de
    ld (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 11*2), hl
    ld (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 23*2), hl
    ld hl, (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 8*2)
    add hl, de
    ld (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 8*2), hl
    ld hl, (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 20*2)
    add hl, de
    ld (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 20*2), hl
    ld hl, (L5e9f_3d_vertex_coordinates_after_rotation_matrix)
    ld de, (L5e63_3d_vertex_coordinates_relative_to_player + 6*2)
    add hl, de    
    ld (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 12*2), hl
    ld hl, (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 15*2)
    add hl, de
    ld (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 15*2), hl
    ld hl, (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 18*2)
    add hl, de
    ld (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 18*2), hl
    ld hl, (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 21*2)
    add hl, de
    ld (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 21*2), hl
    ld hl, (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 1*2)
    ld de, (L5e63_3d_vertex_coordinates_relative_to_player + 7*2)
    add hl, de
    ld (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 13*2), hl
    ld hl, (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 16*2)
    add hl, de
    ld (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 16*2), hl
    ld hl, (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 19*2)
    add hl, de
    ld (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 19*2), hl
    ld hl, (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 22*2)
    add hl, de
    ld (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 22*2), hl
    ld hl, (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 2*2)
    ld de, (L5e63_3d_vertex_coordinates_relative_to_player + 8*2)
    add hl, de
    ld (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 14*2), hl
    ld hl, (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 17*2)
    add hl, de
    ld (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 17*2), hl
    ld hl, (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 20*2)
    add hl, de
    ld (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 20*2), hl
    ld hl, (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 23*2)
    add hl, de
    ld (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 23*2), hl
    ld a, 8  ; Number of vertices
    call L9246_object_visibility_check
    jp nz, L97ba_return
    ld hl, L6b6d_cube_edges
    ld (L5f24_shape_edges_ptr), hl
    ld iy, (L749d_object_currently_being_processed_ptr)
    ld hl, L6b86_face_definition_for_cubes + 1
    xor a
    ld (L5e5f_add_to_projected_objects_flag), a
    ld a, (L5e62_player_collision_with_object_flags)
    ld c, a
    ld b, 3
    ld de, 6
    ; Calculate the attributes to use for each face,
    ; This loop iterates 3 times (one per axis), and in each iteration,
    ; we compute the attribute of the two faces associated to that axis.
L9776_axis_loop:
    sra c
    jr c, L977e
    ; This face is not visible:
    ld (hl), 0
    jr L978b_next_face
L977e:
    ; Get the attribute of the first face of the axis:
    ld a, (iy + OBJECT_ADDITIONAL_DATA)
    and #0f
    ld (hl), a
    jr z, L978b_next_face
    ; OPTIMIZATION: There is no point on this code, we should just change the line above to jr nz, L97ba_return
    ; Mark that we should not render the object.
    ld a, 1
    ld (L5e5f_add_to_projected_objects_flag), a
L978b_next_face:
    add hl, de
    sra c
    jr c, L9794
    ld (hl), 0
    jr L97a7
L9794:
    ; Get the attribute of the second face of the axis:
    ld a, (iy + OBJECT_ADDITIONAL_DATA)
    srl a
    srl a
    srl a
    srl a
    ld (hl), a
    jr z, L97a7
    ; OPTIMIZATION: There is no point on this code, we should just change the line above to jr nz, L97ba_return
    ; Mark that we should not render the object.
    ld a, 1
    ld (L5e5f_add_to_projected_objects_flag), a
L97a7:
    add hl, de
    inc iy
    djnz L9776_axis_loop

    ld a, (L5e5f_add_to_projected_objects_flag)
    or a
    jr z, L97ba_return
    xor a
    ld iy, L6b86_face_definition_for_cubes
    call L92b0_project_object_and_add_to_render_list
L97ba_return:
    ret


; --------------------------------
; This method is used for synthesizing other solid shapes than cubes, and projecting them.
; It works as follows:
; - First the function determines the obeject type by comparing some of its dimensions.
; - Once the type of object is determined, the different vertices of the object are synthesized based on these dimensions.
;   - To do this, the code stores the 4 additional dimension data in the object data in (L5f29_extra_solid_dimensions),
;     then, via a collection of cases, it uses those to synthesize vertices.
; - Once we have the vertices, they are transformed, visibility check is carried out, and if it is passed, the object is projected.
; 
; The method is called for objects of type different than rectangle (3), cube (1), or flat shapes (>=10).
; Specifically, the method considers types 4, 5, 6, 7, 8 and 9.
L97bb_project_other_solids:
    ld ix, (L749d_object_currently_being_processed_ptr)
    ; We first determine the shape of the object:
    ; - It seems that rather than relying on the IDs, this code relies on comparing
    ;   the additional dimensions that are stored in the object data starting at offset 12.
    ; - For example, if (ix + 12) != (ix + 14) && (ix + 13) == (ix + 15), the object is considered to be a wedge.
    ld a, (ix + 12)
    cp (ix + 14)
    jr z, L97e5
    ld a, (ix + 13)
    cp (ix + 15)
    jr nz, L97da
    ; Wedge object:
    ld iy, L6bea_face_definition_for_wedges
    ld hl, L6bd7_wedge_edges
    ld a, 6  ; wedges have 6 vertexes
    jr L9801_shape_determined
L97da:
    ; Hourglass object:
    ld iy, L6c50_face_definition_for_hourglasses
    ld hl, L6c37_hourglass_edges
    ld a, 8  ; hourglasses have 8 vertexes
    jr L9801_shape_determined
L97e5:
    ld a, (ix + 13)
    cp (ix + 15)
    jr z, L97f8
    ; Triangle hourglass object:
    ld iy, L6c1a_face_definition_for_triangle_hourglasses
    ld hl, L6c07_triangle_houglass_edges
    ld a, 6  ; triangle hourglasses have 6 vertexes
    jr L9801_shape_determined
L97f8:
    ; Pyramid obect:
    ld iy, L6bbc_face_definition_for_pyramids
    ld hl, L6bab_pyramid_edges
    ld a, 5  ; pyramids have 5 vertexes

L9801_shape_determined:
    ld (L7496_current_drawing_primitive_n_vertices), a
    ld (L5f24_shape_edges_ptr), hl
    ld b, 4
    ld hl, L5f29_extra_solid_dimensions
L980c_extra_dimension_loop:
    ld d, (ix + 12)
    ld e, 0
    srl d
    rr e
    srl d
    rr e  ; de = (ix + 12) * 64
    ld (hl), e  ; save the coordinate in L5f29_extra_solid_dimensions
    inc hl
    ld (hl), d
    inc hl
    inc ix
    djnz L980c_extra_dimension_loop

    ld ix, (L7499_3d_object_bounding_box_relative_to_player_ptr)
    ld a, (L5e61_object_currently_being_processed_type)
    cp 4
    jp nz, L986f

    ; Object type 4:
    ld h, (ix + 11)
    ld l, (ix + 10)
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 2*2), hl
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 11*2), hl
    ld h, (ix + 9)
    ld l, (ix + 8)
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 5*2), hl
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 8*2), hl
    ld de, (L5f29_extra_solid_dimensions + 1*2)
    ld bc, (L5f29_extra_solid_dimensions + 3*2)
    call L985e_project_other_solids_auxiliary_fn1
    ld h, (ix + 1)
    ld l, (ix)
    ld d, (ix + 3)
    ld e, (ix + 2)
    jr L98a3

; Auxiliary local function, since this code is shared by two different object types:
L985e_project_other_solids_auxiliary_fn1:
    push hl
        add hl, de
        ld (L5e63_3d_vertex_coordinates_relative_to_player + 17*2), hl
        ld (L5e63_3d_vertex_coordinates_relative_to_player + 20*2), hl
    pop hl
    add hl, bc
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 14*2), hl
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 23*2), hl
    ret

L986f:
    cp 5
    jp nz, L98ef

    ; Object type 5:
    ld h, (ix + 11)
    ld l, (ix + 10)
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 5*2), hl
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 8*2), hl
    ld h, (ix + 9)
    ld l, (ix + 8)
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 2*2), hl
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 11*2), hl
    ld bc, (L5f29_extra_solid_dimensions + 2)
    ld de, (L5f29_extra_solid_dimensions + 3*2)
    call L985e_project_other_solids_auxiliary_fn1
    ld d, (ix + 1)
    ld e, (ix)
    ld h, (ix + 3)
    ld l, (ix + 2)
L98a3:
    ld (L5e63_3d_vertex_coordinates_relative_to_player), hl
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 3*2), hl
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 6*2), hl
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 9*2), hl
    ex de, hl
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 12*2), hl
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 15*2), hl
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 18*2), hl
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 21*2), hl
    ld h, (ix + 7)
    ld l, (ix + 6)
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 7*2), hl
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 10*2), hl
    ld h, (ix + 5)
    ld l, (ix + 4)
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 2), hl
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 4*2), hl
    push hl
        ld de, (L5f29_extra_solid_dimensions)
        add hl, de
        ld (L5e63_3d_vertex_coordinates_relative_to_player + 13*2), hl
        ld (L5e63_3d_vertex_coordinates_relative_to_player + 19*2), hl
    pop hl
    ld de, (L5f29_extra_solid_dimensions + 2*2)
    add hl, de
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 16*2), hl
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 22*2), hl
    jp L9a73_object_vertices_created
L98ef:
    cp 6
    jr nz, L9935

    ; Object type 6:
    ld h, (ix + 3)
    ld l, (ix + 2)
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 6*2), hl
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 9*2), hl
    ld h, (ix + 1)
    ld l, (ix)
    ld (L5e63_3d_vertex_coordinates_relative_to_player), hl
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 3*2), hl
    ld de, (L5f29_extra_solid_dimensions)
    ld bc, (L5f29_extra_solid_dimensions + 2*2)
    call L9924_project_other_solids_auxiliary_fn2
    ld d, (ix + 5)
    ld e, (ix + 4)
    ld h, (ix + 7)
    ld l, (ix + 6)
    jr L9969

; Auxiliary local function, since this code is shared by two different object types:
L9924_project_other_solids_auxiliary_fn2:
    push hl
        add hl, de
        ld (L5e63_3d_vertex_coordinates_relative_to_player + 12*2), hl
        ld (L5e63_3d_vertex_coordinates_relative_to_player + 18*2), hl
    pop hl
    add hl, bc
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 15*2), hl
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 21*2), hl
    ret

L9935:
    cp 7
    jp nz, L99b5

    ; Object type 7:
    ld h, (ix + 3)
    ld l, (ix + 2)
    ld (L5e63_3d_vertex_coordinates_relative_to_player), hl
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 3*2), hl
    ld h, (ix + 1)
    ld l, (ix)
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 6*2), hl
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 9*2), hl
    ld bc, (L5f29_extra_solid_dimensions)
    ld de, (L5f29_extra_solid_dimensions + 2*2)
    call L9924_project_other_solids_auxiliary_fn2
    ld h, (ix + 5)
    ld l, (ix + 4)
    ld d, (ix + 7)
    ld e, (ix + 6)
L9969:
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 13*2), hl
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 16*2), hl
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 19*2), hl
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 22*2), hl
    ex de, hl
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 2), hl
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 4*2), hl
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 7*2), hl
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 10*2), hl
    ld h, (ix + 11)
    ld l, (ix + 10)
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 5*2), hl
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 8*2), hl
    ld h, (ix + 9)
    ld l, (ix + 8)
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 2*2), hl
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 11*2), hl
    push hl
    ld de, (L5f29_extra_solid_dimensions + 2)
    add hl, de
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 14*2), hl
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 23*2), hl
    pop hl
    ld de, (L5f29_extra_solid_dimensions + 3*2)
    add hl, de
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 17*2), hl
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 20*2), hl
    jp L9a73_object_vertices_created

L99b5:
    cp 8
    jr nz, L99fb_object_type_9

    ; Object type 8:
    ld h, (ix + 7)
    ld l, (ix + 6)
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 2), hl
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 10*2), hl
    ld h, (ix + 5)
    ld l, (ix + 4)
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 4*2), hl
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 7*2), hl
    ld de, (L5f29_extra_solid_dimensions + 2)
    ld bc, (L5f29_extra_solid_dimensions + 3*2)
    call L99ea_project_other_solids_auxiliary_fn3
    ld d, (ix + 9)
    ld e, (ix + 8)
    ld h, (ix + 11)
    ld l, (ix + 10)
    jr L9a2a

; Auxiliary local function, since this code is shared by two different object types:
L99ea_project_other_solids_auxiliary_fn3:
    push hl
        add hl, de
        ld (L5e63_3d_vertex_coordinates_relative_to_player + 16*2), hl
        ld (L5e63_3d_vertex_coordinates_relative_to_player + 19*2), hl
    pop hl
    add hl, bc
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 13*2), hl
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 22*2), hl
    ret

L99fb_object_type_9:
    ; Object type 9:
    ld h, (ix + 7)
    ld l, (ix + 6)
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 4*2), hl
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 7*2), hl
    ld h, (ix + 5)
    ld l, (ix + 4)
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 2), hl
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 10*2), hl
    ld bc, (L5f29_extra_solid_dimensions + 2)
    ld de, (L5f29_extra_solid_dimensions + 3*2)
    call L99ea_project_other_solids_auxiliary_fn3
    ld h, (ix + 9)
    ld l, (ix + 8)
    ld d, (ix + 11)
    ld e, (ix + 10)
L9a2a:
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 14*2), hl
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 17*2), hl
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 20*2), hl
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 23*2), hl
    ex de, hl
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 2*2), hl
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 5*2), hl
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 8*2), hl
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 11*2), hl
    ld h, (ix + 3)
    ld l, (ix + 2)
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 6*2), hl
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 9*2), hl
    ld h, (ix + 1)
    ld l, (ix)
    ld (L5e63_3d_vertex_coordinates_relative_to_player), hl
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 3*2), hl
    push hl
        ld de, (L5f29_extra_solid_dimensions)
        add hl, de
        ld (L5e63_3d_vertex_coordinates_relative_to_player + 12*2), hl
        ld (L5e63_3d_vertex_coordinates_relative_to_player + 18*2), hl
    pop hl
    ld de, (L5f29_extra_solid_dimensions + 2*2)
    add hl, de
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 15*2), hl
    ld (L5e63_3d_vertex_coordinates_relative_to_player + 21*2), hl

L9a73_object_vertices_created:
    ; At this point all the vertices of the object have been synthesized,
    ; and we are ready to transform it and potentially project it.
    push iy
        call L850f_apply_rotation_matrix_to_object_vertices
        ld a, (L7496_current_drawing_primitive_n_vertices)
        call L9246_object_visibility_check
    pop iy
    jr nz, L9ac4_return
    ld ix, (L749d_object_currently_being_processed_ptr)
    ld d, 0
    ld b, (iy)
    ; The following loop reads the texture IDs of each face and assigns them.
    ; Each iteration of the loop has 2 parts:
    ; - one reading the least significant nibble, and one reading the most significant one
    ; - this is because each byte encodes the texture of two faces. So, each full loop
    ;   assigns textures to two faces.
    push iy
        inc iy
L9a8f:
        ld a, (ix + OBJECT_ADDITIONAL_DATA)
        and #0f
        ld (iy), a
        ld e, (iy + 1)
        inc e
        inc e
        add iy, de
        djnz L9aa2
        ; If the number of faces is odd, we will eventually end the loop here:
        jr L9abd_pop_iy_project_object_and_return
L9aa2:
        ld a, (ix + OBJECT_ADDITIONAL_DATA)
        and #f0
        srl a
        srl a
        srl a
        srl a
        ld (iy), a
        ld e, (iy + 1)
        inc e
        inc e
        add iy, de
        inc ix
        djnz L9a8f
L9abd_pop_iy_project_object_and_return:
    pop iy
    ld a, 1
    call L92b0_project_object_and_add_to_render_list
L9ac4_return:
    ret


; --------------------------------
; - Computes the object bounding box in player-relative coordinates.
; - Then projects all the vertices from 3d to 2d.
; - If the object is within the viewport, it adds it to the rendering list.
; - Called to project objects with ID >= 10
; - When this function is called this has already happened:
;   - rendering cube volume has been calculated
;   - rotation matrix has already been set
;   - cube volume culling check has been done
;   - player_collision_with_object_flags has been set
;   - object bounding box coordinates relative to player have been stored in
;     (L7499_3d_object_bounding_box_relative_to_player_ptr)
L9ac5_project_flat_shape_object:
    ld ix, (L749d_object_currently_being_processed_ptr)
    ld a, (L5e61_object_currently_being_processed_type)
    sub 8
    ld (L7496_current_drawing_primitive_n_vertices), a
    ld b, a
    ld a, (ix + 9)
    ld (L746a_current_drawing_texture_id), a

    ; This loop calculates the object vertex coordinates, relative the the player by
    ; subtracting the player coordinates from them, and stores them in
    ; (L5e63_3d_vertex_coordinates_relative_to_player).
    ld iy, L5e63_3d_vertex_coordinates_relative_to_player
L9adc_vertex_loop:
    push bc
        ld hl, L6aad_player_current_x
        ld b, 3
        ; Iterate 3 times: one for x, one for y, one for z.
L9ae2_3_coordinates_loop:
        ld e, (hl)
        inc hl
        ld d, (hl)  ; de = player coordinate
        inc hl
        push hl
            ld h, (ix + 10)
            ld l, 0
            srl h
            rr l
            srl h
            rr l  ; hl = vertex coordinate * 64
            or a
            sbc hl, de  ; subtract the player coordinate
            ld (iy), l
            ld (iy + 1), h
            inc iy
            inc iy
            inc ix
        pop hl
        djnz L9ae2_3_coordinates_loop
    pop bc
    djnz L9adc_vertex_loop

    call L850f_apply_rotation_matrix_to_object_vertices
    ld a, (L7496_current_drawing_primitive_n_vertices)
    call L9246_object_visibility_check
    jr nz, L9b5a_object_not_visible
    ld iy, L6cb0_face_definition_for_flat_objects
    ld a, (L7496_current_drawing_primitive_n_vertices)
    ld (L6cb0_face_definition_for_flat_objects + 2), a
    cp 2
    jr nz, L9b30_more_than_2_vertexes

    ; Object is a line (2 vertexes):
    ld hl, L6c75_line_edges
    ld a, (L746a_current_drawing_texture_id)
    and #0f
    ld (L6cb0_face_definition_for_flat_objects + 1), a
    xor a
    jr L9b54

L9b30_more_than_2_vertexes:
    ; Object has more than 2 vertexes:

    ; If it has 3 vertexes
    ld hl, L6c7a_triangle_edges_top
    ld de, L6c81_triangle_edges_bottom
    cp 3
    jr z, L9b4a

    ; If it has 4 vertexes
    ld hl, L6c88_rectangle_edges_top
    ld de, L6c91_rectangle_edges_bottom
    cp 4
    jr z, L9b4a  ; If it has 4 vertexes

    ; If it has 5 vertexes
    ld hl, L6c9a_pentagon_edges_top
    ld de, L6ca5_pentagon_edges_bottom
L9b4a:
    ld (iy + 1), 1  ; L6cb0_face_definition_for_flat_objects + 1
    ld (L5f26_alternative_shape_edges_ptr), de
    ld a, 2
L9b54:
    ld (L5f24_shape_edges_ptr), hl
    call L92b0_project_object_and_add_to_render_list
L9b5a_object_not_visible:
    ret


; --------------------------------
; Projects a rectangle. Using the object bounding box, generates the 3d vertices for a rectangle, and
; then calls the projection method for adding them to the render list.
; Called to project objects with type "OBJECT_TYPE_RECTANGLE"
; - When this function is called this has already happened:
;   - rendering cube volume has been calculated
;   - rotation matrix has already been set
;   - cube volume culling check has been done
;   - player_collision_with_object_flags has been set
;   - object bounding box coordinates relative to player have been stored in
;     (L7499_3d_object_bounding_box_relative_to_player_ptr)
L9b5b_project_rectangle_objects:
    ld iy, (L749d_object_currently_being_processed_ptr)
    ld a, (L5e62_player_collision_with_object_flags)
    ld c, a
    ld a, (iy + OBJECT_SIZE_X)
    ld b, (iy + OBJECT_SIZE_Y)
    ld d, (iy + OBJECT_ADDITIONAL_DATA)
    ; Assume x == 0
    ld ix, L5e63_3d_vertex_coordinates_relative_to_player + 6*2  ; vertex 3
    ld iy, L5e63_3d_vertex_coordinates_relative_to_player + 3*2  ; vertex 2
    or a
    jr z, L9b93_rectangle_orientation_set  ; If rectangle has size x == 0, we guessed right
    ; Rectangle has size x != 0:
    ; Assume y == 0
    ld ix, L5e63_3d_vertex_coordinates_relative_to_player  ; vertex 1
    ld iy, L5e63_3d_vertex_coordinates_relative_to_player + 6*2  ; vertex 3
    srl c
    srl c
    ld a, b
    or a
    jr z, L9b93_rectangle_orientation_set  ; If rectangle has size y == 0, we guessed right
    ; Rectangle is vertical (has size y != 0):
    ld ix, L5e63_3d_vertex_coordinates_relative_to_player + 3*2  ; vertex 3
    ld iy, L5e63_3d_vertex_coordinates_relative_to_player  ; vertex 1
    srl c
    srl c
L9b93_rectangle_orientation_set:
    ; At this point:
    ; - ix, iy point to the two vertexes we need to edit
    ; - the lowest 2 bits of c indicate the player collision wrt to the flat dimension of the rectangle.
    ld a, d  ; a == object additional data.
    bit 0, c  ; Check if player is above or below the rectangle
    jr z, L9ba2
    ; Player is above the rectangle:
    and #f  ; get rectangle attribute (top face)
    jp z, L9c2c_return  ; If it's transparent, we are done
    ld hl, L6c91_rectangle_edges_bottom
    jr L9bb2_attribute_obtained
L9ba2:
    and #f0  ; get rectangle attribute (bottom face)
    jp z, L9c2c_return  ; If it's transparent, we are done
    srl a
    srl a
    srl a
    srl a  ; shift the attribute/texture to be in the lowest 4 bits.
    ld hl, L6c88_rectangle_edges_top
L9bb2_attribute_obtained:
    ; At this point:
    ; - ix, iy point to the two vertexes we need to edit
    ; - a: attribute (texture) to use
    ; - hl: edge pointer
    ld (L6cb0_face_definition_for_flat_objects + 1), a
    ld (L5f24_shape_edges_ptr), hl

    ; Generate the 4 vertices of the rectangle, based on the information above:
    push ix
    push iy
        call L9177_rotate_relative_bounding_box
    pop iy
    pop ix
    ld hl, (L5e9f_3d_vertex_coordinates_after_rotation_matrix)
    ld e, (ix)
    ld d, (ix + 1)
    add hl, de
    ld (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 3*2), hl
    ld c, (iy)
    ld b, (iy + 1)
    add hl, bc
    ld (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 6*2), hl
    or a
    sbc hl, de
    ld (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 9*2), hl
    ld hl, (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 1*2)
    ld e, (ix + 2)
    ld d, (ix + 3)
    add hl, de
    ld (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 4*2), hl
    ld c, (iy + 2)
    ld b, (iy + 3)
    add hl, bc
    ld (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 7*2), hl
    or a
    sbc hl, de
    ld (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 10*2), hl
    ld hl, (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 2*2)
    ld e, (ix + 4)
    ld d, (ix + 5)
    add hl, de
    ld (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 5*2), hl
    ld c, (iy + 4)
    ld b, (iy + 5)
    add hl, bc
    ld (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 8*2), hl
    or a
    sbc hl, de
    ld (L5e9f_3d_vertex_coordinates_after_rotation_matrix + 11*2), hl
    ld a, 4
    ld (L6cb0_face_definition_for_flat_objects + 2), a  ; Number of vertices of this object.
    call L9246_object_visibility_check
    jr nz, L9c2c_return
    xor a
    ld iy, L6cb0_face_definition_for_flat_objects
    call L92b0_project_object_and_add_to_render_list
L9c2c_return:
    ret


; --------------------------------
; Sorts the projected objects in the order we should render them using bubble sort.
L9c2d_sort_objects_for_rendering:
    ld a, (L746b_n_objects_to_draw)
    push af
L9c31_whole_object_pass_loop:
    pop af
    dec a
    jp z, L9d45_ret
    jp m, L9d45_ret
    push af
        ld hl, L6754_current_room_object_projected_data + 2
        ; Initialize the flag that will trigger another sorting iteration:
        xor a
        ld (L5f32_sorting_any_change), a
        ld a, (L746b_n_objects_to_draw)
        dec a  ; Iterate for n_objects - 1 (since we are comparing one object with the next for sorting).
L9c45_objects_loop:
        push af
            push hl
                ; Get the pointer to bounding box from the first object:
                ld e, (hl)
                inc hl
                ld d, (hl)
                ld (L5f33_sorting_boundingbox_ptr1), de
                inc hl
                ; Get the pointer to bounding box from the second object:
                inc hl  ; skip the vertex pointer
                inc hl
                ld e, (hl)
                inc hl
                ld d, (hl)
                ld (L5f35_sorting_boundingbox_ptr2), de
                xor a
                ld (L5f31_sorting_comparison_result), a
                ld ix, (L5f33_sorting_boundingbox_ptr1)  ; ptr to object 1 bounding box (relative to player)
                ld iy, (L5f35_sorting_boundingbox_ptr2)  ; ptr to object 2 bounding box (relative to player)
                ld b, 3
                ; 3 iterations, one for X, one for Y, one for Z:
                ; I annotated the coordinates as "x1", "x2" below, but that's only for the first
                ; iteration, after that it's y1, y2, and then z1, z2.
L9c66_bounding_box_axis_loop:
                ; Each iteration writes 2 bits, so, shift this 2 bits to the left:
                ld hl, L5f31_sorting_comparison_result
                ld a, (hl)
                add a, a
                add a, a
                ld (hl), a

                ld d, (iy + 3)
                ld e, (iy + 2)  ; de = bbox2.x2
                ld (L5f3d_sorting_bbox2_c2), de
                ld h, (ix + 1)
                ld l, (ix)  ; hl = bbox1.x1
                ld (L5f37_sorting_bbox1_c1), hl
                or a
                sbc hl, de  ; hl = bbox1.x1 - bbox2.x2 (only used to check which is larger)
                ld d, (ix + 3)
                ld e, (ix + 2)  ; de = bbox1.x2
                ld h, (iy + 1)
                ld l, (iy)  ; hl = bbox2.x1
                ld (L5f39_sorting_bbox2_c1), hl
                jp p, L9c9b_one_object_clearly_further_than_the_other
                or a
                sbc hl, de  ; hl = bbox2.x1 - bbox1.x2
                jp m, L9cf3_objects_incomparable_in_this_axis

L9c9b_one_object_clearly_further_than_the_other:
                ld (L5f3b_sorting_bbox1_c2), de  ; bbox1.x2
                ld a, (L5f37_sorting_bbox1_c1 + 1)  ; bbox1.x1
                and #80  ; keep the sign
                ld e, a  ; sign of bbox1.x1
                ld a, d
                and #80  ; keep the sign
                cp e
                ; If object 1 has a bounding box that covers the 0 coordinate, and does not overlap with the other object,
                ; it must be closer to the player in this axis:
                jr nz, L9ce6_first_object_is_closer
                ; Object 1 is completely to one side of the player, not directly in front:
                ld a, (L5f3d_sorting_bbox2_c2 + 1)
                and #80  ; keep the sign
                ld d, a
                ld a, (L5f39_sorting_bbox2_c1 + 1)
                and #80  ; keep the sign
                cp d
                ; If object 2 has a bounding box that covers the 0 coordinate, and does not overlap with the other object,
                ; it must be closer to the player in this axis:
                jr nz, L9cec_second_object_is_closer

                ; Object 2 is completely to one side of the player, not directly in front:
                cp e
                ; if each object is in a different side, we cannot make any judgement
                jr nz, L9cf3_objects_incomparable_in_this_axis

                ; Both objects are on the same side of the player:
                ; Compare their coordinates and check which is closer (taking into account the sign):
                ld de, (L5f37_sorting_bbox1_c1)
                ld hl, (L5f39_sorting_bbox2_c1)
                ld a, h
                and #80  ; keep the sign
                sbc hl, de
                jr z, L9cd3
                ld l, a
                ld a, h
                and #80  ; keep the sign
                cp l
                jr z, L9ce6_first_object_is_closer
                jr L9cec_second_object_is_closer
L9cd3:
                ld hl, (L5f3d_sorting_bbox2_c2)
                ld de, (L5f3b_sorting_bbox1_c2)
                ld a, h
                and #80  ; keep the sign
                sbc hl, de
                ld l, a
                ld a, h
                and #80  ; keep the sign
                cp l
                jr nz, L9cec_second_object_is_closer
L9ce6_first_object_is_closer:
                ld hl, L5f31_sorting_comparison_result
                inc (hl)  ; mark object 1 closer
                jr L9cf3_objects_incomparable_in_this_axis
L9cec_second_object_is_closer:
                ld hl, L5f31_sorting_comparison_result
                ld a, (hl)
                or 2  ; mark object 2 closer
                ld (hl), a
L9cf3_objects_incomparable_in_this_axis:
                ; We cannot make any judgement, just move to the next object:
                ld de, 4
                add ix, de
                add iy, de
                dec b
                jp nz, L9c66_bounding_box_axis_loop
                ld c, 4
            pop hl
            ld a, (L5f31_sorting_comparison_result)
            ; If object 2 is clearly closer in one axis, keep order as is:
            cp #20
            jr z, L9d37_next_object
            cp #08
            jr z, L9d37_next_object
            cp #02
            jr z, L9d37_next_object
            ; If object 2 is clearly closer in more than one axis, also keep order as is:
            cp #28
            jr z, L9d37_next_object
            cp #0a
            jr z, L9d37_next_object
            cp #22
            jr z, L9d37_next_object
            cp #2a
            jr z, L9d37_next_object

            ; Otherwise, swap objects:
            ld a, 1
            ld (L5f32_sorting_any_change), a
            ld d, h
            ld e, l
            dec hl
            dec hl
            inc de
            inc de
            ld b, c  ; b = 4
            ; To flip the objects, we just need to flip the two pointers,
            ; the one to vertices, and the one to the bounding boxes.
L9d2c_flip_objects_loop:
            ld c, (hl)
            ld a, (de)
            ld (hl), a
            ld a, c
            ld (de), a
            inc hl
            inc de
            djnz L9d2c_flip_objects_loop
            ld c, 2
L9d37_next_object:
            add hl, bc
        pop af
        dec a
        jp nz, L9c45_objects_loop
        ld a, (L5f32_sorting_any_change)
        or a
        jp nz, L9c31_whole_object_pass_loop  ; if any change has happened, we need to do another pass
    pop af
L9d45_ret:
    ret


; --------------------------------
; Renders all the objects in the current room, and potentially the background, if necessary.
; After rendering the room, it overlays the movement pointer if active.
L9d46_render_3d_view:
    ld a, (L746b_n_objects_to_draw)
    ld d, a
    ld a, (L7481_n_objects_covering_the_whole_screen)
    or a
    jr z, L9d73_do_not_skip_objects
    ld (L5f3f_n_objects_covering_the_whole_screen_left), a
    ; When there are objects covering the whole screen, there is no point drawing everything that
    ; is behind them, so, we skip all objects until we reach those:
    ld hl, L6754_current_room_object_projected_data
L9d56_skip_object_loop:
    ld c, (hl)
    inc hl
    ld b, (hl)
    inc hl
    inc hl
    inc hl
    inc bc
    ld a, (bc)  ; number of primitives
    or a
    jr z, L9d6e
    bit 7, a
    jr z, L9d6e
    ld a, (L5f3f_n_objects_covering_the_whole_screen_left)
    dec a
    ld (L5f3f_n_objects_covering_the_whole_screen_left), a
    jr z, L9d84_objects_loop_entry_point
L9d6e:
    dec d
    jr z, L9dae_done_drawing_objects
    jr L9d56_skip_object_loop

L9d73_do_not_skip_objects:
    ; Note: the background (including the skybox) is only drawn when
    ; there are no objects to skip (i.e. no object covers the whole screen). This is because,
    ; otherwise, it would be a waste of time as the object covering the whole scree would occlude it.
    call La2ff_render_background
    ld hl, L6754_current_room_object_projected_data
L9d79_objects_loop:
    ld a, d
    or a
    jr z, L9dae_done_drawing_objects
    ; Get the pointer to the primitive (vertex) data:
    ld c, (hl)
    inc hl
    ld b, (hl)
    inc hl
    inc hl
    inc hl
    inc bc  ; skip object ID
L9d84_objects_loop_entry_point:
    ld a, (bc)
    or a  ; number of primitives to draw
    jr z, L9dab_done_drawing_object
    and #7f
    inc bc  ; skip the number of primitives byte
    push bc
    pop ix
    ld b, a
    ; b: number of primitives to draw for the current object.
L9d8f_primitive_loop:
    ld a, (ix)
    ; Read object type and texture:
    ; a = xxxxyyyy: 'xxxx' is the texture ID, 'yyyy' is the number of vertices.
    inc ix
    ld c, a
    srl a
    srl a
    srl a
    srl a
    ld (L746a_current_drawing_texture_id), a
    ld a, c
    and #0f
    ld (L7496_current_drawing_primitive_n_vertices), a
    call L92ec_draw_primitive
    djnz L9d8f_primitive_loop
L9dab_done_drawing_object:
    dec d
    jr L9d79_objects_loop
L9dae_done_drawing_objects:
    ld a, (L6b1c_movement_or_pointer)
    or a
    jr nz, L9dbb
    ld a, (L6b20_display_movement_pointer_flag)
    or a
    call nz, Lcd8c_draw_movement_center_pointer
L9dbb:
    ret


; --------------------------------
; Changes the viewport attributes if necessary, and renders the render buffer to
; video memory.
; Also, if requested via 'L7477_render_buffer_effect', it applies an effect such
; as fade-in, or opening/closing the gate over the viewport.
L9dbc_render_buffer_with_effects:
    push af
        ld a, (L7469_n_spirits_found_in_current_area)
        ld (L6b2a_spirit_in_room), a
        ld a, (L7466_need_attribute_refresh_flag)
        or a
        call nz, Lb252_set_screen_area_attributes
        ld a, (L7477_render_buffer_effect)
        or a
        jr nz, L9dd6_render_effect
        call La298_render_buffer_render
        jp L9ddf
L9dd6_render_effect:
        cp 1
        call z, Lb579_render_buffer_fade_in
        scf
        call nz, Lce09_gate_open_close_effect
L9ddf:
        call Lb548_draw_pointer_if_pointer_mode
    pop af
    ret


; --------------------------------
; Variables used by "L9dec_game_tick".
L9de4_pressed_keys_functions:
    db #e6, #7f, #03, #c5, #dd  ; Stores the game functions of all the keys currently held down by the player.
L9de9_current_key_index:
    db #e1
L9dea_game_over_reason_message:
    ; If you die, this contains the reason for which you died.
    db #47, #dd


; --------------------------------
; Executes one game update tick:
; - Reads player input from keyboard/joystick
; - Executes the desired actions
; - Checks if the game is over and displays game over screen
L9dec_game_tick:
    ld hl, 0
    ld (L746c_game_flags), hl
    ld a, h
    ld (L7480_under_pointer_object_ID), a
    ld (L7477_render_buffer_effect), a  ; no render effect
    ld (L747f_player_event), a
    ld (L7473_timer_event), a
    ld (L747a_requested_SFX), a
    ld (L7476_trigger_collision_event_flag), a
    ld (L6b2b_desired_eye_compass_frame), a
    ld (L9de9_current_key_index), a
    ld a, (L6b0e_lightning_time_seconds_countdown)
    or a
    jr nz, L9e53_countdown_not_zero
    ; Each time the second countdown reaches zero, if (L6b19_current_area_flags) is != 0, there is a lightning
    ld a, r
    and #3f
    add a, 10
    ld (L6b0e_lightning_time_seconds_countdown), a  ; (L6b0e_lightning_time_seconds_countdown) = 10 + randint(0, 64)
    ld a, (L6b19_current_area_flags)
    or a
    jr z, L9e53_countdown_not_zero
    ld a, (L6add_desired_attribute_color)
    push af
        ; Change attributes, and wait for one interrupt:
        and #c7
        or #38
        ld (L6add_desired_attribute_color), a
        xor a
        ld (L7478_interrupt_executed_flag), a
L9e2f_wait_for_interrupt_loop:
        ld a, (L7478_interrupt_executed_flag)
        or a
        jr z, L9e2f_wait_for_interrupt_loop
        call Lb252_set_screen_area_attributes
    pop af
    ; Restore attributes, and wait for another interrupt:
    ld (L6add_desired_attribute_color), a
    xor a
    ld (L7478_interrupt_executed_flag), a
L9e40_wait_for_interrupt_loop:
    ld a, (L7478_interrupt_executed_flag)
    or a
    jr z, L9e40_wait_for_interrupt_loop
    call Lb252_set_screen_area_attributes

    ld a, SFX_LIGHTNING
    call Lc4ca_play_SFX
    ld a, 8
    ld (L746c_game_flags + 1), a

L9e53_countdown_not_zero:
    ld a, (L6adf_game_boolean_variables + 3)
    bit 6, a
    jr z, L9e63
    ld a, GAME_OVER_REASON_ESCAPED
    ld (L7479_current_game_state), a
    push af
        jp L9f25_game_over
L9e63:
    ld a, (L7475_call_Lcba4_check_for_player_falling_flag)
    or a
    jr z, L9e75_regular_control
    ld a, (L7479_current_game_state)
    or a
    jr nz, L9e75_regular_control
    call Lcba4_check_for_player_falling
    jp L9fa0_ret
L9e75_regular_control:
    call Lbfd4_read_keyboard_and_joystick_input
    push af
        ld a, (L7479_current_game_state)
        or a
        jp nz, L9f25_game_over
        ld hl, L6b21_time_unit6_previous
        ld a, (L6b22_time_unit6)
        cp (hl)
        jr z, L9e8f
        ld (hl), a
        ld a, 8
        ld (L7473_timer_event), a
L9e8f:
    pop af
    jp nc, L9fa0_ret  ; no key pressed
    ; Some key was pressed:
    ; Go through the pressed keys, and use the input mapping to identify their functions
    ld a, (L749f_number_of_pressed_keys)
    ld b, a
    ld de, L9de4_pressed_keys_functions
    ld ix, L74a0_pressed_keys_buffer
L9e9e_check_pressed_keys_loop:
    push bc
        ld c, (ix)
        ld hl, L7684_input_mapping
        ld b, 3*4  ; the 4 movement keys have 3 possible bindings per key
        ld a, c
L9ea8_movement_key_loop:
        cp (hl)
        inc hl
        jr z, L9ebe_key_found
        inc hl
        inc hl
        djnz L9ea8_movement_key_loop
        ld b, 13  ; There are 13 other keys to check (each encoded as a 2 byte pair):
        ld a, c
L9eb3_other_key_loop:
        cp (hl)
        inc hl
        jr z, L9ec5_key_found
        inc hl
        djnz L9eb3_other_key_loop
        ld a, 127  ; no function
        jr L9ec6_save_key_game_function
L9ebe_key_found:
        ld a, (L6b1c_movement_or_pointer)
        or a
        jr z, L9ec5_key_found
        inc hl
L9ec5_key_found:
        ld a, (hl)
L9ec6_save_key_game_function:
        ld (de), a  ; store the function of the pressed key
        inc de
        inc ix  ; next key press
    pop bc
    djnz L9e9e_check_pressed_keys_loop
    ; Now that we have stored all the requested game functions by key presses,
    ; Go through them one by one and execute them:
    ld a, (L9de4_pressed_keys_functions)
L9ed0_check_request_key_functions_loop:
    cp 1
    jp m, L9edf
    cp 21
    jp p, L9edf
    call Laee5_executes_movement_related_pressed_key_functions
    jr L9f10_next_key_function
L9edf:
    cp 21
    jp m, L9f06
    cp 31
    jp p, L9f06
    cp 22
    jr nz, L9f01_process_key_function
    ; Throw rock:
    ld b, a
    ld a, (L6b1c_movement_or_pointer)
    or a
    ld a, b
    jr nz, L9f01_process_key_function
    ; If we want to throw a rock in "movement" mode, we do:
    ; - first toggle the mode (function 30)
    ; - then throw the rock (function 22)
    ; - tootle mode again (function 30)
    ld a, INPUT_SWITCH_BETWEEN_MOVEMENT_AND_POINTER
    call Lb2f9_execute_pressed_key_function
    ld a, INPUT_THROW_ROCK
    call Lb2f9_execute_pressed_key_function
    ld a, INPUT_SWITCH_BETWEEN_MOVEMENT_AND_POINTER
L9f01_process_key_function:
    call Lb2f9_execute_pressed_key_function
    jr L9f10_next_key_function
L9f06:
    cp INPUT_INFO_MENU  ; player requested load/save/quit menu?
    jr nz, L9f10_next_key_function
    call Lc224_load_save_quit_menu
    jp L9fa0_ret
L9f10_next_key_function:
    ld hl, L9de9_current_key_index
    ld a, (L749f_number_of_pressed_keys)
    inc (hl)
    cp (hl)
    jp z, L9fa0_ret  ; If we have checked them all, we are done
    ; Get the next requested key function:
    ld c, (hl)
    ld b, 0
    ld hl, L9de4_pressed_keys_functions
    add hl, bc
    ld a, (hl)
    jr L9ed0_check_request_key_functions_loop

L9f25_game_over:
    ; Game over: "a" contains the reason for this to happen.
    ; Draw the game text # "a"
    pop hl  ; To cancel "push af" without destroying "a".
    ld b, a
    ld hl, L6cb9_game_text
    ld de, 16
L9f2d_find_text_loop:
    add hl, de
    djnz L9f2d_find_text_loop
    ld ix, L735a_ui_message_row_pointers
    ld de, #0f00
    ld (L9dea_game_over_reason_message), hl
    call Ld01c_draw_string
    cp GAME_OVER_REASON_ESCAPED
    call z, L9fa1_escape_castle_sequence
    jr z, L9f4d_prepare_game_stats_for_game_over

    cp GAME_OVER_REASON_CRUSHED
    call nz, L9d46_render_3d_view
    or a  ; reset carry flag (to set a close gate animation)
    call Lce09_gate_open_close_effect

L9f4d_prepare_game_stats_for_game_over:
    call Lc39b_update_number_of_collected_keys_text
    call Lc3cb_update_number_of_spirits_destroyed_text
    call Lc3b8_update_score_text
    ld ix, L735a_ui_message_row_pointers
    ld de, #0f00

L9f5d_display_game_score_loop:
    ; Loops alternating score, collected keys and spirits destroyed, 
    ; (flipping between them once per second), until a key is pressed.
    call L9f83_pause_of_exit_with_key
    ld hl, L7d6a_text_score
    call Ld01c_draw_string
    call L9f83_pause_of_exit_with_key
    ld hl, L7d4a_text_collected
    call Ld01c_draw_string
    call L9f83_pause_of_exit_with_key
    ld hl, L7d5a_text_destroyed
    call Ld01c_draw_string
    call L9f83_pause_of_exit_with_key
    ld hl, (L9dea_game_over_reason_message)
    call Ld01c_draw_string
    jr L9f5d_display_game_score_loop

L9f83_pause_of_exit_with_key:
    ld a, 50  ; 1 second pause
    ld (L74a5_interrupt_timer), a
L9f88_pause_or_wait_for_key_loop:
    call Lbfd4_read_keyboard_and_joystick_input
    jr c, L9f94_exit_indicating_game_is_over
    ld a, (L74a5_interrupt_timer)
    or a
    jr nz, L9f88_pause_or_wait_for_key_loop
    ret

L9f94_exit_indicating_game_is_over:
    pop hl  ; simulate a ret, to get out of the "L9f5d" loop
    ld a, SFX_MENU_SELECT
    call Lc4ca_play_SFX
    ld hl, 2  ; flag that indicates game is over
    ld (L746c_game_flags), hl
L9fa0_ret:
    ret


; --------------------------------
; Game ending sequence: rotates the player toward the castle, and moves away.
L9fa1_escape_castle_sequence:
    push af
        ld hl, 4
        ld (L746c_game_flags), hl
        ; Start by automatically rotating the player to have:
        ; - yaw = FULL_ROTATION_DEGREES / 2
        ; - pitch = 0
        ld de, #0202
        ld a, (L6ab7_player_yaw_angle)
        cp FULL_ROTATION_DEGREES / 2
        jr c, L9fb4_turn_right
        ld e, -2
L9fb4_turn_right:
        ld a, (L6ab6_player_pitch_angle)
        cp FULL_ROTATION_DEGREES / 2
        jr nc, L9fbd_look_down
        ld d, -2
L9fbd_look_down:
L9fbd_rotate_loop:
        ld a, (L6ab7_player_yaw_angle)
        cp FULL_ROTATION_DEGREES / 2
        jr nz, L9fcc_yaw_updated
        ; We have the desired "yaw", so, no "yaw" rotation:
        ld e, 0
        ld a, (L6ab6_player_pitch_angle)
        or a
        jr z, L9fe7_facing_the_desired_direction
L9fcc_yaw_updated:
        ld a, (L6ab7_player_yaw_angle)
        add a, e
        ld (L6ab7_player_yaw_angle), a
        ld a, (L6ab6_player_pitch_angle)
        or a
        jr z, L9fdf_pitch_updated
        add a, d
        cp FULL_ROTATION_DEGREES
        jr nz, L9fdf_pitch_updated
        xor a
L9fdf_pitch_updated:
        ld (L6ab6_player_pitch_angle), a
        call L83aa_redraw_whole_screen
        jr L9fbd_rotate_loop

L9fe7_facing_the_desired_direction:
        ; We are facing the desired direction, now move the player away from the castle.
        ld de, 512  ; desired movement speed
        ld a, 1
        ld (L6abd_cull_by_rendering_volume_flag), a  ; do not cull by volume, render everything!
L9fef_movement_loop:
        ld hl, (L6ab1_player_current_z)
        add hl, de
        ld a, h
        and 192
        jr nz, La000_ending_sequence_done
        ld (L6ab1_player_current_z), hl
        call L83aa_redraw_whole_screen
        jr L9fef_movement_loop
La000_ending_sequence_done:
    pop af
    ret


; --------------------------------
; Auxiliary variables for La005_check_rules
; Script that is triggered when interacting with an object that
; has no rules no rule was found for the event, and the player collided:
La002_script_size:
    db 2  ; 2 bytes
La003_script:
    ; Rule that matches with a "movement event" (as there are no extra flags in the first byte),
    ; and triggers an SFX.
    db RULE_TYPE_REQUEST_SFX_NEXT_FRAME, SFX_MENU_SELECT


; --------------------------------
; If a player of timer event was triggered, check if any rule needs to be triggered.
; This function checks rules in:
; - The current selected object
; - The global game rules
; - The current area rules
La005_check_rules:
    ld hl, L747f_player_event
    ld a, (L7473_timer_event)
    or (hl)
    ret z  ; If there are no player nor timer events, return.

    ld (hl), a  ; save the aggregate of L747f_player_event and L7473_timer_event in L747f_player_event.
    ld a, (L7480_under_pointer_object_ID)
    or a
    jr z, La050_check_global_rules
    ld (L7468_focus_object_id), a
    ; Find the selected object:
    xor a
    call Lb286_find_object_by_id
    or a
    jr nz, La050_check_global_rules  ; If we could not find it, skip
    ; We found the selected object!
    ld a, (ix)
    and #0f  ; a = object type

    ld iy, L6b2c_expected_object_size_by_type
    ld e, a
    ld d, 0
    add iy, de
    ld e, (iy)  ; e = expected size of this object (anything beyond is rules).
    ld a, (ix + OBJECT_SIZE)
    sub e
    jr z, La040_no_rule_data_in_the_object
    add ix, de
    call Lb7e2_execute_script
    ld a, (L7471_event_rule_found)
    or a
    jr nz, La050_check_global_rules
La040_no_rule_data_in_the_object:
    ld a, (L7476_trigger_collision_event_flag)
    or a
    jr z, La050_check_global_rules
    ; Player collided with an object, trigger the default collision rule:
    ld a, (La002_script_size)  ; size
    ld ix, La003_script  ; rules
    call Lb7e2_execute_script

La050_check_global_rules:
    ld ix, (L746e_global_rules_ptr)
    ld a, (ix)  ; a = number of scripts
    or a
    jr z, La06c_global_rules_done
    inc ix
    ld b, a

La05d_global_script_loop:
    ld a, (ix)  ; size of the script
    inc ix
    call Lb7e2_execute_script
    ld e, a
    ld d, 0
    add ix, de  ; next script
    djnz La05d_global_script_loop

La06c_global_rules_done:
    ld ix, (L6ad5_current_area_rules)
    ld a, (ix)  ; a = number of rules
    or a
    jr z, La088_done
    inc ix
    ld b, a
La079_current_area_script_loop:
    ld a, (ix)  ; script size
    inc ix
    call Lb7e2_execute_script
    ld e, a
    ld d, 0
    add ix, de  ; next script
    djnz La079_current_area_script_loop
La088_done:
    ret


; --------------------------------
; 3x3 Matrix multiplication:
; L5e55_rotation_matrix = L5e55_rotation_matrix * L5e4c_pitch_rotation_matrix
La089_3x3_matrix_multiply:
    ld hl, L5f40_16_bit_tmp_matrix
    ld (L5f52_16_bit_tmp_matrix_ptr), hl
    ld ix, L5e4c_pitch_rotation_matrix
    ld iy, L5e55_rotation_matrix
    ld b, 3
    ; Multiply L5e4c_pitch_rotation_matrix by L5e55_rotation_matrix,
    ; And store the result (16bits per number) in L5f52_16_bit_tmp_matrix_ptr
La099_matmul_row_loop:
    push bc
        ld b, 3
La09c_matmul_column_loop:
        push bc
            ld b, 3
            ld de, 0
La0a2_matmul_inner_loop:
            push bc
                ld h, (ix)
                inc ix
                ld l, (iy)
                ld bc, 3
                add iy, bc
                call La253_h_times_l_signed
                add hl, de
                ex de, hl  ; de += h * l
            pop bc
            djnz La0a2_matmul_inner_loop
            ld hl, (L5f52_16_bit_tmp_matrix_ptr)
            ld (hl), e
            inc hl
            ld (hl), d
            inc hl
            ld (L5f52_16_bit_tmp_matrix_ptr), hl
            ld bc, -3
            add ix, bc
            ld bc, -8
            add iy, bc
        pop bc
        djnz La09c_matmul_column_loop
        ld bc, 3
        add ix, bc
        ld bc, -3
        add iy, bc
    pop bc
    djnz La099_matmul_row_loop
    ; Copy the 16bit results over to the 8 bit matrix "L5e55_rotation_matrix" 
    ld b, 9
    ld ix, L5f40_16_bit_tmp_matrix
    ld iy, L5e55_rotation_matrix
La0e6:
    ; the 8bit value is constructed by dividing the 16bit one by 4:
    ld d, (ix + 1)
    sla (ix)
    rl d
    sla (ix)
    rl d
    bit 7, (ix)
    jr z, La0fc_positive
    inc d
La0fc_positive:
    ld (iy), d
    inc iy
    inc ix
    inc ix
    djnz La0e6
    ret


; --------------------------------
; Signed multiplication between A and HL.
; The signed 24 bit result is returned in (A,HL)
; Input:
; - a
; - hl
; Output:
; - a, hl
La108_a_times_hl_signed:
    or a
    jr nz, La10e
    ld h, a
    ld l, a
    ret
La10e:
    push bc
        ld b, a
        ld a, l
        or h
        jr nz, La116
    pop bc
    ret
La116:
        ld c, 0
        bit 7, b
        jr z, La121
        ld a, b
        neg
        ld b, a
        inc c
La121:
        bit 7, h
        jr z, La130
        ld a, h
        cpl
        ld h, a
        ld a, l
        cpl
        ld l, a
        inc hl
        ld a, c
        xor 1
        ld c, a
La130:
        push de
            ld a, b
            ex de, hl
            ld hl, 0
            ld b, 8
La138:
            sla a
            jr c, La144
            djnz La138
            jr La15b
La140:
            add hl, hl
            rla
            jr nc, La147
La144:
            add hl, de
            adc a, 0
La147:
            djnz La140
            bit 0, c
            jr z, La15b
            cpl
            ld b, a
            ld a, h
            cpl
            ld h, a
            ld a, l
            cpl
            ld l, a
            ld a, b
            ld de, 1
            add hl, de
            adc a, d
La15b:
        pop de
    pop bc
    ret


; --------------------------------
; Signed multiplication between DE and HL.
; The signed 32 bit result is returned in (DE,HL)
; Input:
; - de
; - hl
; Output:
; - de, hl
La15e_de_times_hl_signed:
    push af
        ld a, h
        or l
        jr nz, La167
        ld d, a
        ld e, a
        pop af
    ret
La167:
        ld a, d
        or e
        jr nz, La16f
        ld h, a
        ld l, a
    pop af
    ret
La16f:
        push bc
            ld c, 0
            bit 7, h
            jr z, La17e
            ld a, h
            cpl
            ld h, a
            ld a, l
            cpl
            ld l, a
            inc hl
            inc c
La17e:
            bit 7, d
            jr z, La18d
            ld a, d
            cpl
            ld d, a
            ld a, e
            cpl
            ld e, a
            inc de
            ld a, c
            xor 1
            ld c, a
La18d:
            push bc
                ld a, h
                ld c, l
                ld b, 16
                ld hl, 0
La195:
                sla c
                rla
                jr c, La1a7
                djnz La195
                ld d, b
                ld e, b
            pop bc
            jr La1c9
La1a1:
                add hl, hl
                rl c
                rla
                jr nc, La1ae
La1a7:
                add hl, de
                jr nc, La1ae
                inc c
                jr nz, La1ae
                inc a
La1ae:
                djnz La1a1
                ld d, a
                ld e, c
            pop bc
            bit 0, c
            jr z, La1c9
            ld a, h
            cpl
            ld h, a
            ld a, l
            cpl
            ld l, a
            ld a, d
            cpl
            ld d, a
            ld a, e
            cpl
            ld e, a
            inc hl
            ld a, l
            or h
            jr nz, La1c9
            inc de
La1c9:
        pop bc
    pop af
    ret


; --------------------------------
; Signed division between (A,HL) and DE.
; Result stored in (A,HL)
; Input:
; - a, hl
; - de
; Output:
; - a, hl
La1cc_a_hl_divided_by_de_signed:
    push bc
        ld b, a
        or l
        jr nz, La1d8
        or h
        jr nz, La1d8
        ld d, a
        ld e, a
    pop bc
    ret
La1d8:
        ld c, 0
        bit 7, d
        jr z, La1e6
        ld a, d
        cpl
        ld d, a
        ld a, e
        cpl
        ld e, a
        inc de
        inc c
La1e6:
        ld a, b
        bit 7, a
        jr z, La1fe
        cpl
        ld b, a
        ld a, h
        cpl
        ld h, a
        ld a, l
        cpl
        ld l, a
        ld a, c
        xor 1
        ld c, a
        inc hl
        ld a, l
        or h
        ld a, b
        jr nz, La1fe
        inc a
La1fe:
        ld b, a
        ld a, c
        exx
        push bc
            ld c, a
            exx
            ld a, b
            or a
            ld b, 24
La208:
            rl l
            rl h
            rla
            jr c, La215
            djnz La208
            ld d, b
            ld e, b
            jr La251
La215:
            ld c, a
            ld a, b
            exx
                ld b, a
            exx
            ld a, c
            ld b, h
            ld c, l
            ld hl, 0
            jr La228
La222:
            exx
            rl c
            rl b
            rla
La228:
            adc hl, hl
            sbc hl, de
            jr nc, La22f
            add hl, de
La22f:
            ccf
            exx
                djnz La222
            exx
            rl c
            rl b
            rla
            ex de, hl
            ld h, b
            ld l, c
            exx
            bit 0, c
        pop bc
        exx
        jr z, La251
        cpl
        ld c, a
        ld a, h
        cpl
        ld h, a
        ld a, l
        cpl
        ld l, a
        ld a, c
        ld bc, 1
        add hl, bc
        adc a, b
La251:
    pop bc
    ret


; --------------------------------
; Signed multiplication between H and L.
; The signed 16 bit result is returned in HL
; Input:
; - h
; - l
; Output:
; - hl
La253_h_times_l_signed:
    push af
        ld a, l
        or a
        jr nz, La25c
        ld h, 0
        pop af
    ret
La25c:
        ld a, h
        or a
        jr nz, La264
        ld l, 0
    pop af
    ret
La264:
        push bc
        push de
            ld c, 0
            bit 7, h
            jr z, La271
            ld a, h
            neg
            ld h, a
            dec c
La271:
            bit 7, l
            jr z, La27d
            ld a, l
            neg
            ld l, a
            ld a, 255
            sub c
            ld c, a
La27d:
            ld a, c
            ld e, l
            ld d, 0
            ld l, d
            ld b, 8
La284:
            add hl, hl
            jr nc, La288
            add hl, de
La288:
            djnz La284
            or a
            jr z, La294
            ld a, h
            cpl
            ld h, a
            ld a, l
            cpl
            ld l, a
            inc hl
La294:
        pop de
        pop bc
        pop af
    ret


; --------------------------------
; Renders the render buffer to video memory
La298_render_buffer_render:
    push ix
    push hl
    push de
    push bc
    push af
        ld ix, L725c_videomem_row_pointers
        ld a, SCREEN_HEIGHT * 8
        ld hl, L5cbc_render_buffer
La2a7_row_loop:
        ld e, (ix)
        ld d, (ix + 1)
        inc ix
        inc ix
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        dec a
        jp nz, La2a7_row_loop
        ld a, (L747a_requested_SFX)
        or a
        call nz, Lc4ca_play_SFX
        xor a
        ld (L747a_requested_SFX), a
    pop af
    pop bc
    pop de
    pop hl
    pop ix
    ret


; --------------------------------
La2f7_skybox_n_rows_to_draw:
    db 0
La2f8_skybox_n_rows_to_skip:
    db 0
La2f9_lightning_height:
    db 0
La2fa_lightning_frame:
    db 0
La2fb_floor_texture_id:
    db #21
La2fc_sky_texture_id:
    db #5c
La2fd_lightning_x:
    dw 0


; --------------------------------
; Renders the background of the 3d scene.
; The background includes:
; - sky
; - potentially mountains (if we are outdoors)
; - floor
; - potentially a lightning
La2ff_render_background:
    push hl
    push de
    push bc
    push af
        xor a
        ld (La2f7_skybox_n_rows_to_draw), a
        ld (La2f8_skybox_n_rows_to_skip), a
        ld (La2f9_lightning_height), a
        ld (La2fa_lightning_frame), a
        ld a, (L6b19_current_area_flags)
        or a
        jp z, La3ec_done
        ld b, a
        and #0f
        ld (La2fc_sky_texture_id), a
        ld a, b
        and #f0
        srl a
        srl a
        srl a
        srl a
        ld (La2fb_floor_texture_id), a
        jp z, La3b6_no_floor_texture
        ld a, (La2fc_sky_texture_id)
        or a
        jp z, La3bf_no_sky_texture
        ld a, (L6ab6_player_pitch_angle)
        cp 8
        jp m, La349_both_sky_and_floor_visible  ; player looking down only a bit
        cp 29
        jp m, La3bf_no_sky_texture  ; player looking down heavily (sky is not visible)
        cp 61
        jp m, La3b6_no_floor_texture  ; player is looking up a lot (floor is not visible)
        sub FULL_ROTATION_DEGREES  ; making the angle in between [-36, 36]
La349_both_sky_and_floor_visible:
        ; Player is not looking too down or too up, hence both floor and sky are visible:
        ; Determine the number of rows of sky and floor, notice that, since the screen is
        ; 112/113 pixels tall, the number of rows of sky + floor must add up to 113.
        ld bc, #7100  ; b = 113, c = 0 (number of rows to draw for sky / floor)
        ld hl, 11
        call La108_a_times_hl_signed  ; hl = pitch * 11
        ld de, 60
        or a
        adc hl, de  ; hl = pitch * 11 + 60
        ld a, l  ; a = (pitch * 11 + 60) % 256
        jp m, La366
        ld c, a
        cp 113
        jr c, La366
        ; no sky, all floor: (set c = 113, and b = 0)
        ld c, b
        ld b, 0
        jr La3c6_number_of_rows_of_sky_floor_decided
La366:
        ld d, a
        ld a, (L6b0e_lightning_time_seconds_countdown)
        or a
        ld a, d
        jr nz, La391
        ; L6b0e_lightning_time_seconds_countdown == 0: draw a lightning
        ; Here: 
        ; - a = (pitch * 11 + 60) % 256
        ; - hl = pitch * 11 + 60
        ld de, 96
        adc hl, de
        ld d, a  ; save a temporarily
        jp m, La390  ; The player is looking too down for the lightning to be visible, skip
        ld a, l
        ld hl, La2f9_lightning_height
        ld (hl), a
        cp 87
        jr c, La390
        ld (hl), 86
        cp 114
        jr c, La390
        ld a, b
        sub c
        sub 10
        ld (hl), a
        ld a, 86
        sub (hl)
        inc hl  ; hl = La2fa_lightning_frame
        ld (hl), a
La390:
        ld a, d  ; restore the value we had in a 
La391:
        ld hl, La2f7_skybox_n_rows_to_draw
        add a, 18
        jp m, La3b0
        ld (hl), a
        cp 19
        jr c, La3b0
        ld (hl), 18
        cp 114
        jr c, La3b0
        ld a, b
        sub c
        ld (hl), a
        ld a, 18
        sub (hl)
        inc hl  ; hl = La2f8_skybox_n_rows_to_skip
        ld (hl), a
        ld b, 0
        jr La3c6_number_of_rows_of_sky_floor_decided
La3b0:
        ld a, b
        sub c
        sub (hl)
        ld b, a
        jr La3c6_number_of_rows_of_sky_floor_decided
La3b6_no_floor_texture:
        ld b, 113
        xor a
        ld (La2f7_skybox_n_rows_to_draw), a
        ld c, a
        jr La3c6_number_of_rows_of_sky_floor_decided
La3bf_no_sky_texture:
        xor a
        ld (La2f7_skybox_n_rows_to_draw), a
        ld b, a
        ld c, 113
La3c6_number_of_rows_of_sky_floor_decided:
        ; Here:
        ; b: number of sky rows to draw
        ; c: number of floor rows to draw
        ld hl, L5cbc_render_buffer
        ld a, b
        or a
        jr z, La3d3_sky_drawn
        ld a, (La2fc_sky_texture_id)
        call La3f1_draw_floor_sky_texture
La3d3_sky_drawn:
        ld a, (La2f7_skybox_n_rows_to_draw)
        or a
        call nz, La416_draw_skybox  ; draws the mountains
        ld a, (La2f9_lightning_height)
        or a
        call nz, La474_draw_lightning
        ld a, c
        or a
        jr z, La3ec_done  ; If there are no floor rows to draw, we are done.
        ld b, c
        ld a, (La2fb_floor_texture_id)
        call La3f1_draw_floor_sky_texture
La3ec_done:
    pop af
    pop bc
    pop de
    pop hl
    ret


; --------------------------------
; Draws the floor texture.
; Input:
; - hl: pointer to where to draw the skybox/floor
; - a: texture ID
; - b: n skybox/floor rows to draw
La3f1_draw_floor_sky_texture:
    ex de, hl
        ld hl, Ld088_texture_patterns
        dec a
        add a, a
        add a, a
        push bc
            ld c, a
            ld b, 0
            add hl, bc
        pop bc
    ex de, hl
    ; Here:
    ; - hl: pointer to where to draw
    ; - de: Ld088_texture_patterns + (a-1)*4
La3ff_floor_draw_loop_y:
    push bc
    push de
        ; Get the appropriate byte of the texture for this row:
        ld a, b
        and #03
        ld c, a
        ld b, 0
        ex de, hl
            add hl, bc
        ex de, hl
        ld a, (de)
        ld b, SCREEN_WIDTH
La40d_floor_draw_loop_x:
        ld (hl), a
        inc hl
        djnz La40d_floor_draw_loop_x
    pop de
    pop bc
    djnz La3ff_floor_draw_loop_y
    ret


; --------------------------------
; Draws the skybox. In this case, a range of mountains.
; Input:
; - hl: pointer to where to draw
La416_draw_skybox:
    ld a, (L6acf_current_area_id)
    cp 1  ; wilderness
    jr z, La426
    ; If we are not outdoors, do not draw mountains:
    ld a, (La2f7_skybox_n_rows_to_draw)
    ld b, a
    ld a, (La2fc_sky_texture_id)
    jr La3f1_draw_floor_sky_texture
La426:
    ; Draw outdoors skybox
    push bc
        push hl
            ld a, (L6ab7_player_yaw_angle)
            and #07
            add a, a
            ld hl, L78f2_background_mountains_gfx
            ld e, a
            ld d, 0
            add hl, de  ; Get the byte where to start reading the mountain graphic (to get horizontal rotation) 
            sub 16
            neg
            ; Calculate the number of bytes left to draw in a row from 
            ; the place where we start reading:
            ld c, a  ; c = 16 - (yaw_angle % 8)
            ; Skip rows of the mountain:
            ld a, (La2f8_skybox_n_rows_to_skip)
            or a
            jr z, La446_no_rows_to_skip
            ld b, a
            ld e, 16
La443_vertical_offset_loop:
            add hl, de
            djnz La443_vertical_offset_loop
La446_no_rows_to_skip:
        pop de
        ld a, (La2f7_skybox_n_rows_to_draw)
        ld b, a
La44b_drawing_loop_y:
        push bc
            push hl
                ; Each row is drawn in two parts:
                ; - The first part is starting from some offset, and we draw until the end
                ; - Then, we "wrap-around" the row, and start drawing from the beginning, until we fill one row of the screen.
                ; - Since we want to draw 24 bytes (screen width), and skybox is 16 bytes in width,
                ;   we might need to loop a couple of times.
                ; Draw the first part of the row:
                ld a, SCREEN_WIDTH
                ld b, 0
                sub c
                ldir
                ; Draw the second part of the row:
La454_drawing_loop_x:
                ld bc, -16
                add hl, bc
                cp 17
                jr c, La465_no_need_for_more_loops
                ld bc, 16
                ldir
                sub 16
                jr La454_drawing_loop_x
La465_no_need_for_more_loops:
                ld c, a
                ld b, 0
                ldir
            pop hl
            ld c, 16
            add hl, bc
        pop bc
        djnz La44b_drawing_loop_y
        ex de, hl
    pop bc
    ret


; --------------------------------
; Draws a lightning at a random horizontal position in the screen
La474_draw_lightning:
    ld a, r
La476_modulo_20_loop:
    cp 20
    jr c, La47e_a_lower_than_20
    sub 20
    jr La476_modulo_20_loop
La47e_a_lower_than_20:
    ; a = random number between [0, 19]
    ld (La2fd_lightning_x), a
    push hl
    push bc
        ld a, (La2f9_lightning_height)
        ld b, a
        ld a, (La2f7_skybox_n_rows_to_draw)
        sub 8
        jr nc, La48f
        xor a
La48f:
        add a, b
        ex de, hl
            ld h, a
            ld l, -SCREEN_WIDTH
            call La253_h_times_l_signed
            add hl, de
        ex de, hl
        ld hl, L7a9b_lightning_gfx
        ld a, (La2fa_lightning_frame)
        add a, a
        ld c, a
        ld b, 0
        add hl, bc
        ex de, hl
        ; Here:
        ; - hl = a * -SCREEN_WIDTH + ptr where to start drawing after sky/mountains
        ; - de = L7a9b_lightning_gfx + (La2fa_lightning_frame) * 2
        ld a, (La2f9_lightning_height)
        ld b, a
La4a9_row_loop:
        push bc
            push hl
                ld bc, (La2fd_lightning_x)  ; Add a random amount (in [0, 20])
                add hl, bc
                ex de, hl
                    ld b, 2
La4b3_loop:
                    ; Note: this rendering code does not make sense. The effect is just
                    ; adding the mask as an "or", but it does it in a very convoluted
                    ; and wasteful way.
                    ld a, (de)  ; read a pixel from the screen
                    ld c, a
                    cpl  ; invert it
                    and (hl)  ; apply and mask
                    or c  ; add the original pixel again
                    ld (de), a  ; write it back to screen
                    inc hl
                    inc de
                    djnz La4b3_loop
                ex de, hl
            pop hl
            ld bc, SCREEN_WIDTH
            add hl, bc
        pop bc
        djnz La4a9_row_loop
    pop bc
    pop hl
    ret


; --------------------------------
; Resets the game state to start a new game.
La4c9_init_game_state:
    push ix
    push hl
    push de
    push bc
    push af
        ld a, 1
        ld (L7479_current_game_state), a
        ld a, 63
        ld (L747b), a
        ld a, 255
        ld (L6b20_display_movement_pointer_flag), a
        ld a, 32  ; Initial value of the spirit meter
        ld (L6b1f_current_spirit_meter), a
        xor a
        ld (L747a_requested_SFX), a
        ld (L6b1c_movement_or_pointer), a
        ld (L6b1e_time_unit5), a
        ld (L7474_check_if_object_crushed_player_flag), a
        ld (L7475_call_Lcba4_check_for_player_falling_flag), a
        ld b, (L6b0d_new_key_taken - L6adf_game_boolean_variables) + 1  ; 47 bytes
        ld hl, L6adf_game_boolean_variables
La4f8_mem_init_loop:
        ld (hl), a
        inc hl
        djnz La4f8_mem_init_loop
        ld a, (L6b23_set_bit7_byte_3_flag_at_start)
        or a
        jr z, La507
        ld hl, L6adf_game_boolean_variables + 3
        set 7, (hl)
La507:
        ld a, (Ld087_starting_strength)
        ld (L6b0a_current_strength), a
        ld a, 2
        ld (L6ab8_player_crawling), a  ; start not crawling
        ld (L6b0b_selected_movement_mode), a  ; start running
        call Lc0f0_get_initial_area_pointers
        ld a, (Ld082_n_areas)
        ld c, a
        ld hl, Ld0d1_area_offsets
La51f_area_loop:
        ld e, (hl)
        inc hl
        ld d, (hl)
        inc hl
        ld ix, Ld082_area_reference_start
        add ix, de  ; ix = ptr to the area.
        ld a, (ix + AREA_N_OBJECTS)
        or a
        jr z, La54a_done_with_objects
        ld de, AREA_HEADER_SIZE
        add ix, de
        ld b, a
La535_object_loop:
        ; Reset the state of each object:
        ld a, (ix + OBJECT_TYPE_AND_FLAGS)
        and #8f
        bit 7, a
        jr z, La540
        or #40
La540:
        ld (ix), a
        ld e, (ix + OBJECT_SIZE)
        add ix, de
        djnz La535_object_loop
La54a_done_with_objects:
        dec c
        jr nz, La51f_area_loop
        ld a, (Ld085_initial_area_id)
        ld (L6acf_current_area_id), a
        ld a, (Ld086_initial_player_object)
        ld (L7467_player_starting_position_object_id), a
        call La563_load_and_reset_new_area
    pop af
    pop bc
    pop de
    pop hl
    pop ix
    ret


; --------------------------------
; Searches and loads the area with ID (L6acf_current_area_id),
; teleporting the player to the desired start position (L7467_player_starting_position_object_id).
La563_load_and_reset_new_area:
    push ix
    push hl
    push de
    push bc
    push af
        call Lc143_load_and_reset_current_area
        ld a, (L7467_player_starting_position_object_id)
        ld (L7468_focus_object_id), a
        xor a
        call Lb286_find_object_by_id
        or a
        jr nz, La5c5_done
        ld de, 32
        ld b, d
        ld a, (ix + OBJECT_X)
        cp 255
        jr z, La58b
        inc b
        call La5cc_a_times_64
        ld (L6aad_player_current_x), hl
La58b:
        ld a, (ix + OBJECT_Z)
        cp 255
        jr z, La599
        inc b
        call La5cc_a_times_64
        ld (L6ab1_player_current_z), hl
La599:
        ld a, (ix + OBJECT_Y)
        cp 255
        jr z, La5b4
        inc b
        ld h, a
        ld a, (L6abe_use_eye_player_coordinate)
        or a
        jr nz, La5ae
        ; Adjust player y to be "eye" coordinate.
        ld a, (L6ab9_player_height)
        dec a
        add a, h
        ld h, a
La5ae:
        call La5cd_h_times_64
        ld (L6aaf_player_current_y), hl
La5b4:
        ld a, 3
        cp b
        jr nz, La5c5_done
        ld a, (ix + OBJECT_SIZE_X)
        ld (L6ab6_player_pitch_angle), a
        ld a, (ix + OBJECT_SIZE_Y)
        ld (L6ab7_player_yaw_angle), a
La5c5_done:
    pop af
    pop bc
    pop de
    pop hl
    pop ix
    ret


; --------------------------------
; HL = a * 64
; input:
; - a
; - de
; output:
; - hl = a*64 + de
La5cc_a_times_64:
    ld h, a
La5cd_h_times_64:
    ld l, 0
    srl h
    rr l
    srl h
    rr l
    add hl, de
    ret


; --------------------------------
; Attempts a player movement:
; Input:
; - desired player coordinates in (L7456_player_desired_x, ...)
; Output:
; - modifies (L6aad_player_current_x, ...)
; - a: 1 if movement, 0 otehrwise.
La5d9_move_player:
    push ix
    push hl
    push de
    push bc
        ld a, (L6b28_player_radius)
        or a
        jr z, La634_target_within_bounds  ; Cannot happen in this game (player ratius is always 10).
        ld hl, (L7456_player_desired_x)
        ld a, h
        cp #7f
        jr z, La61f_pop_and_return  ; out of bounds in x
        cp #9f
        jr z, La61f_pop_and_return  ; out of bounds in x
        ld de, (L745a_player_desired_z)
        ld a, d
        cp #7f
        jr z, La61f_pop_and_return  ; out of bounds in z
        cp #9f
        jr z, La61f_pop_and_return  ; out of bounds in z
        xor a
        ld bc, MAX_COORDINATE
        call La623_coordinates_positive_and_small_check
        sla a
        ld hl, (L6aad_player_current_x)
        ld de, (L6ab1_player_current_z)
        call La623_coordinates_positive_and_small_check
        or a  ; both out of bounds
        jp z, La8cc_accept_movement  ; if we are already out of bounds, just move
        cp 3  ; both within bounds
        jr z, La634_target_within_bounds
        cp 1  ; target within bounds
        jr z, La634_target_within_bounds
        ; origin within bounds
        jp La8cc_accept_movement  ; if target is out of bounds, accept movement
La61f_pop_and_return:
        xor a  ; mark "no movement".
        jp La923_pop_and_return

; Auxiliary function of La5d9_move_player: checks if some x, z coordinates are within some bounds.
; input:
; - hl: x
; - de: z
; - bc: 127*64  (MAX_COORDINATE)
; output:
; - if the (x, z) coordinates are positive and smaller than bc, a++
La623_coordinates_positive_and_small_check:
    ; x out of bounds?
    bit 7, h  ; if x is negative -> return
    ret nz
    or a
    sbc hl, bc  ; hl -= bc
    ret p  ; if x is too large -> return
    ; z out of bounds?
    bit 7, d
    ret nz  ; if z is negative -> return
    ex de, hl
    or a
    sbc hl, bc  ; hl = de - bc
    ret p  ; if z is too large -> return
    ; success, coordiantes are positive and small:
    inc a  ; a++
    ret

La634_target_within_bounds:
        ; The target coordinates have passed the "La623_coordinates_positive_and_small_check":
        xor a
        ld (L74e5_collision_correction_object_shape_type), a
        ld (L74e6_movement_involves_falling_flag), a
        ld (L74eb_closest_object_below_ID), a
        ld h, a
        ld l, a
        ld (L74e3_player_height_16bits), hl
        dec hl
        ld (L74d0_target_object_climb_coordinates + 2), hl  ; #ffff
        ld b, a  ; b = 0
        ld a, (L6b28_player_radius)
        ld c, a
        or a
        jr z, La650
        dec c  ; bc = radius - 1
La650:
        ; At this point:
        ; - bc = max(0, player radius - 1)
        ld a, (L6abe_use_eye_player_coordinate)
        or a
        jr nz, La677  ; jump if "eye coordinates":
        ; feet coordinates (used when we are checking if we need to fall):
        ld a, 2
        ld (L74e6_movement_involves_falling_flag), a
        ld hl, (L6aad_player_current_x)
        ld (L74dc_falling_reference_coordinates), hl
        ld hl, (L6aaf_player_current_y)
        ld (L74dc_falling_reference_coordinates + 2), hl
        ld hl, (L6ab1_player_current_z)
        ld (L74dc_falling_reference_coordinates + 4), hl
        ld a, (L6ab9_player_height)
        ld h, a
        call La9de_hl_eq_h_times_64
        ld (L74e3_player_height_16bits), hl
La677:
        xor a  ; initialize whether there is movement or not in any axis.
        ld hl, (L7456_player_desired_x)
        ld (L74ca_movement_target_coordinates_2), hl
        ld (L74d6_movement_target_coordinates_1), hl
        ; Check if we are requesting movement in any axis, and in which direction:
        ld de, (L6aad_player_current_x)
        push hl
            or a
            sbc hl, de
            ld (L74a6_player_movement_delta), hl
        pop hl
        jr z, La697
        set 1, a  ; positive movement on x axis
        jp p, La697
        ld a, 1  ; negative movement on x axis
        ex de, hl
La697:
        ; At this point:
        ; - bc = max(0, player radius - 1)
        ; - hl = max(desired x, player x)
        ; - de = min(player x, desired x)
        add hl, bc
        ld (L74ac_movement_volume_max_coordinate), hl  ; max x + radius
        ex de, hl
        or a
        sbc hl, bc
        ld (L74b2_movement_volume_min_coordinate), hl  ; min x - radius
        ld hl, (L7458_player_desired_y)
        ld (L74ca_movement_target_coordinates_2 + 2), hl
        ld (L74d6_movement_target_coordinates_1 + 2), hl
        ld de, (L6aaf_player_current_y)
        push hl
            or a
            sbc hl, de
            ld (L74a6_player_movement_delta + 2), hl
        pop hl
        jr z, La6c3
        set 3, a  ; positive movement on y axis
        jp p, La6c3
        and #f3
        or 4  ; negative movement on y axis
        ex de, hl
La6c3:
        push de
            ld d, a
            ld a, (L6abe_use_eye_player_coordinate)
            or a
            ld a, d
        pop de
        jr nz, La6dd
        ; Feet coordinates: take into account whole player height.
        inc de
        ld (L74b2_movement_volume_min_coordinate + 2), de
        ld de, (L74e3_player_height_16bits)
        add hl, de
        dec hl
        ld (L74ac_movement_volume_max_coordinate + 2), hl
        jr La6e8
La6dd:
        ; Eye coordinates: consider just a cube around the eye coordinates,
        ; ignoring player height.
        add hl, bc
        ld (L74ac_movement_volume_max_coordinate + 2), hl
        ex de, hl
        or a
        sbc hl, bc
        ld (L74b2_movement_volume_min_coordinate + 2), hl

La6e8:
        ld hl, (L745a_player_desired_z)
        ld (L74ca_movement_target_coordinates_2 + 4), hl
        ld (L74d6_movement_target_coordinates_1 + 4), hl
        ld de, (L6ab1_player_current_z)
        push hl
            or a
            sbc hl, de
            ld (L74a6_player_movement_delta + 4), hl
        pop hl
        jr z, La709
        set 5, a  ; positive movement on z axis
        jp p, La709
        and #cf
        or 16  ; negative movement on z axis
        ex de, hl
La709:
        add hl, bc
        ld (L74ac_movement_volume_max_coordinate + 4), hl
        ex de, hl
        or a
        sbc hl, bc
        ld (L74b2_movement_volume_min_coordinate + 4), hl
        or a
        jp z, La923_pop_and_return  ; if there is no movement in any axis, just return
        ld (L74e2_movement_direction_bits), a  ; bits 0,1: movement on x, bits 2,3: movement on y, bits 4,5: movement on z

        ld a, (L6abe_use_eye_player_coordinate)
        or a
        jp nz, La825_movement_without_falling

La722_movement_with_falling:
        ; Feet coordinates movement, consider falling!
        call Laa9f_find_closest_object_below
        ld hl, (L74e7_closest_object_below_distance)
        ld a, l  ; if we are on top of an object, ignore falling
        or h
        jp nz, La825_movement_without_falling

        ; We are falling!
        ld a, (L74eb_closest_object_below_ID)
        or a
        jr z, La785_falling_without_object

        ; Check if in the target x, z we wanted to be over this object
        ; If not, it means the object interrupted x/z movement, and we need to adjust.
        ld ix, (L74e9_closest_object_below_ptr)
        ld h, (ix + OBJECT_X)
        call La9de_hl_eq_h_times_64
        xor a
        ld de, (L7456_player_desired_x)
        sbc hl, de  ; object x * 64 - desired x
        jp p, La78c_object_below_not_really_below
        ld a, (ix + OBJECT_X)
        add a, (ix + OBJECT_SIZE_X)
        ld h, a
        call La9de_hl_eq_h_times_64
        xor a
        sbc hl, de
        jp m, La78c_object_below_not_really_below
        ld h, (ix + OBJECT_Z)
        call La9de_hl_eq_h_times_64
        xor a
        ld de, (L745a_player_desired_z)
        sbc hl, de
        jp p, La78c_object_below_not_really_below
        ld a, (ix + OBJECT_Z)
        add a, (ix + OBJECT_SIZE_Z)
        ld h, a
        call La9de_hl_eq_h_times_64
        xor a
        sbc hl, de
        jp m, La78c_object_below_not_really_below
        
        ; Set the new reference coordinates for falling:
        ld hl, L7456_player_desired_x
        ld de, L74dc_falling_reference_coordinates
        ld bc, 6
        ldir

        ; Find another object (just in case?) and move on 
        ; to regular movement.
        call Laa9f_find_closest_object_below
La785_falling_without_object:
        xor a
        ld (L74e6_movement_involves_falling_flag), a
        jp La825_movement_without_falling

La78c_object_below_not_really_below:
        ; The object we collided with interrupted us half way to reaching
        ; the target x, z. We need to cut the movement short:
        ld a, (L74e2_movement_direction_bits)
        bit 0, a
        jr z, La798
        ; negative x movement
        ld h, (ix + OBJECT_X)
        jr La7a3
La798:
        bit 1, a
        jr z, La7e7
        ; positive x movement
        ld a, (ix + OBJECT_X)
        add a, (ix + OBJECT_SIZE_X)
        ld h, a
La7a3:
        call La9de_hl_eq_h_times_64  ; hl = object x2 * 2
        ld (L74dc_falling_reference_coordinates), hl
        call Lae7b_relative_z_proportional_to_relative_x_and_player_movement_direction
        ld (L74dc_falling_reference_coordinates + 4), hl
        ld d, (ix + OBJECT_Z)
        call La9d3_de_eq_d_times_64
        or a
        push hl
            sbc hl, de
        pop hl
        jp m, La7e7
        ld a, (ix + OBJECT_Z)
        add a, (ix + OBJECT_SIZE_Z)
        ld d, a
        call La9d3_de_eq_d_times_64
        or a
        sbc hl, de
        jp p, La7e7
        ld hl, (L74dc_falling_reference_coordinates)
        ld bc, (L6b28_player_radius)
        ld a, (L74e2_movement_direction_bits)
        bit 0, a
        jr z, La7e0
        or a
        sbc hl, bc
        jr La7e1
La7e0:
        add hl, bc
La7e1:
        ; we have adjusted the coordinates, try again to see now if we can keep falling:
        ld (L74dc_falling_reference_coordinates), hl
        jp La722_movement_with_falling

La7e7:
        ; Movement in 'x' was not interrupted, try to see if movement in 'z' is the one interrupted:
        ld a, (L74e2_movement_direction_bits)
        bit 4, a
        jr z, La7f3
        ld h, (ix + OBJECT_Z)
        jr La7ff
La7f3:
        bit 5, a
        jp z, La825_movement_without_falling
        ld a, (ix + OBJECT_Z)
        add a, (ix + OBJECT_SIZE_Z)
        ld h, a
La7ff:
        call La9de_hl_eq_h_times_64
        ld (L74dc_falling_reference_coordinates + 4), hl
        call Lae96_relative_x_proportional_to_relative_z_and_player_movement_direction
        ld (L74dc_falling_reference_coordinates), hl
        ld hl, (L74dc_falling_reference_coordinates + 4)
        ld bc, (L6b28_player_radius)
        ld a, (L74e2_movement_direction_bits)
        bit 4, a
        jr z, La81e
        or a
        sbc hl, bc
        jr La81f
La81e:
        add hl, bc
La81f:
        ; we have adjusted the coordinates, try again to see now if we can keep falling:
        ld (L74dc_falling_reference_coordinates + 4), hl
        jp La722_movement_with_falling

La825_movement_without_falling:
        ; Eye coordinates movement, do not consider falling:
        call Lab56_correct_player_movement_if_collision
        ld a, (L6b28_player_radius)
        or a
        ld a, 1
        jp z, La923_pop_and_return
        ld a, (L74e6_movement_involves_falling_flag)
        or a
        jr nz, La850_movement_involved_falling
La837:
        ; Movement did not involve falling:
        ; Set L74d6_movement_target_coordinates_1 as our desired move:
        ld hl, L74d6_movement_target_coordinates_1
        ld de, L7456_player_desired_x
        ld bc, 6
        ldir
        ld a, (L7480_under_pointer_object_ID)
        or a
        jr nz, La8af
        ld a, (L74eb_closest_object_below_ID)
        ld (L7480_under_pointer_object_ID), a
        jr La8af

La850_movement_involved_falling:
        ld hl, (L74ca_movement_target_coordinates_2)
        ld de, (L74ca_movement_target_coordinates_2 + 2)
        ld bc, (L74ca_movement_target_coordinates_2 + 4)
        call La9e9_manhattan_distance_to_player
        push hl
            ld hl, (L74dc_falling_reference_coordinates)
            ld de, (L74dc_falling_reference_coordinates + 2)
            ld bc, (L74dc_falling_reference_coordinates + 4)
            call La9e9_manhattan_distance_to_player
        pop de
        or a
        sbc hl, de  ; hl = distance to falling reference - distance to target 2
        jp p, La837  ; target 2 is closer, just go to regular movement without falling
        ; Move player down, and if distance is too large, call Lcb78_fall_from_height
        ld de, (L74e7_closest_object_below_distance)
        ld hl, (L74dc_falling_reference_coordinates + 2)
        xor a
        ld (L7476_trigger_collision_event_flag), a
        sbc hl, de
        ld (L74dc_falling_reference_coordinates + 2), hl
        ld (L7458_player_desired_y), hl
        ld hl, (L74dc_falling_reference_coordinates)
        ld (L7456_player_desired_x), hl
        ld hl, (L74dc_falling_reference_coordinates + 4)
        ld (L745a_player_desired_z), hl
        ex de, hl
        add hl, hl
        add hl, hl
        ld a, (L6aba_max_falling_height_without_damage)
        cp h
        jp p, La8a2  ; jump is fall is acceptable
        call Lcb78_fall_from_height
        jr La8cc_accept_movement

La8a2:
        ; Move down without damage
        ld a, (L74eb_closest_object_below_ID)
        ld (L7480_under_pointer_object_ID), a
        ld a, SFX_CLIMB_DROP
        ld (L747a_requested_SFX), a
        jr La8cc_accept_movement
La8af:
        ld a, (L6abe_use_eye_player_coordinate)
        or a
        jr nz, La8cc_accept_movement
        ; Using feet coordinates (when falling/climbing):
        ld hl, (L74d0_target_object_climb_coordinates + 2)
        bit 7, h
        jr nz, La8cc_accept_movement
        ; See if we tried to climb to high an altitude:
        ld de, (L7458_player_desired_y)
        or a
        sbc hl, de
        add hl, hl
        add hl, hl
        ld a, (L6abb_max_climbable_height)
        cp h
        ; If height is acceptable, climb!
        call nc, La929_teleport_player_if_no_collision

La8cc_accept_movement:
        ; Actually execute the movement:
        ; If player is within bounds, turn on culling, otherwise, turn it off.
        ; My guess is that this is to prevent not rendering anything if player
        ; is too far.
        ; Note: not sure why "La623_coordinates_positive_and_small_check" was
        ;       not used for this, as it's the same logic.
        ; x within bounds:?
        ld de, MAX_COORDINATE
        ld hl, (L7456_player_desired_x)
        bit 7, h
        jr nz, La8e9_no_culling
        or a
        sbc hl, de
        jp p, La8e9_no_culling
        ; z within bounds:?
        ld hl, (L745a_player_desired_z)
        bit 7, h
        jr nz, La8e9_no_culling
        xor a  ; culling
        sbc hl, de
        jp m, La8eb
La8e9_no_culling:
        ld a, 1  ; no culling
La8eb:
        ld (L6abd_cull_by_rendering_volume_flag), a
        ; Copy x coordinate, and mark "a = 1" if there is a change:
        ld de, (L7456_player_desired_x)
        ld hl, (L6aad_player_current_x)
        xor a
        sbc hl, de
        jr z, La8ff
        ld (L6aad_player_current_x), de
        inc a
La8ff:
        ; Copy y coordinate, and mark "a = 1" if there is a change:
        ld de, (L7458_player_desired_y)
        ld hl, (L6aaf_player_current_y)
        or a
        sbc hl, de
        jr z, La911
        ld (L6aaf_player_current_y), de
        ld a, 1
La911:
        ; Copy z coordinate, and mark "a = 1" if there is a change:
        ld de, (L745a_player_desired_z)
        ld hl, (L6ab1_player_current_z)
        or a
        sbc hl, de
        jr z, La923_pop_and_return
        ld (L6ab1_player_current_z), de
        ld a, 1
La923_pop_and_return:
    pop bc
    pop de
    pop hl
    pop ix
    ret


; --------------------------------
; Checks if the player would collide with any visible object if moving to
; coordinates (L74d0_target_object_climb_coordinates), and if there is no collision:
; - sets the player desired coordinates to (L74d0_target_object_climb_coordinates).
; - Sets L7476_trigger_collision_event_flag to 0,
; - Plays an SFX.
; This is used, for example, to teleport the player on top of a short object,
; when colliding with it.
La929_teleport_player_if_no_collision:
    ld ix, (L6ad1_current_area_objects)
    ld a, (L6ad0_current_area_n_objects)
    or a
    call nz, La953_find_object_with_collision
    ld ix, (L7463_global_area_objects)
    ld a, (L7465_global_area_n_objects)
    or a
    call nz, La953_find_object_with_collision
    ; No collision! Set the desired player coordinates to the target coordinates!
    ld (L7476_trigger_collision_event_flag), a  ; a == 0 here
    ld hl, L74d0_target_object_climb_coordinates
    ld de, L7456_player_desired_x
    ld bc, 6
    ldir
    ld a, SFX_CLIMB_DROP
    ld (L747a_requested_SFX), a
La952:
    ret


; --------------------------------
; Checks if there is any object that collides with a vertical line that 
; is at coordinates (L74d0_target_object_climb_coordinates), with height (L74e3_player_height_16bits)
; Input:
; - a: number of objects
; - ix: pointer to first object
La953_find_object_with_collision:
    ld b, a  ; number of objects
La954_object_loop:
    bit 6, (ix)  ; is the object visible?
    jp nz, La9c7_next_object  ; if not visible, skip

    ; "y" coordinate check: check if (L74d0_target_object_climb_coordinates + 2) is within the object bounding box "x":
    ld h, (ix + OBJECT_Y)
    call La9de_hl_eq_h_times_64
    ld de, (L74e3_player_height_16bits)
    or a
    sbc hl, de  ; hl = object y * 64 - (L74e3_player_height_16bits)
    ld de, (L74d0_target_object_climb_coordinates + 2)  ; y
    xor a
    sbc hl, de  ; hl = object y * 64 - ((L74e3_player_height_16bits) + (L74d0_target_object_climb_coordinates + 2))
    ; If (L74e3_player_height_16bits) + (L74d0_target_object_climb_coordinates + 2) < object y * 64, skip
    jp p, La9c7_next_object

    ex de, hl  ; hl = (L74d0_target_object_climb_coordinates + 2)
    ld a, (ix + OBJECT_Y)
    add a, (ix + OBJECT_SIZE_Y)
    ld d, a  ; d = object y2 = object y + object size y 
    call La9d3_de_eq_d_times_64
    xor a
    sbc hl, de
    ; If (L74d0_target_object_climb_coordinates + 2) > object y2 * 64, skip
    jp p, La9c7_next_object

    ; "x" coordinate check: check if (L74d0_target_object_climb_coordinates) is within the object bounding box "x":
    ld d, (ix + OBJECT_X)
    call La9d3_de_eq_d_times_64
    ld hl, (L74d0_target_object_climb_coordinates)  ; x
    xor a
    sbc hl, de
    ; if (L74d0_target_object_climb_coordinates) < object x * 64, skip
    jp m, La9c7_next_object

    ld h, (ix + OBJECT_SIZE_X)
    call La9de_hl_eq_h_times_64
    add hl, de  ; hl = object x2 * 64
    ld de, (L74d0_target_object_climb_coordinates)  ; z
    xor a
    sbc hl, de
    ; if object x2 * 64 < (L74d0_target_object_climb_coordinates), skip
    jp m, La9c7_next_object

    ; "z" coordinate check: check if (L74d0_target_object_climb_coordinates + 4) is within the object bounding box "z":
    ld d, (ix + OBJECT_Z)
    call La9d3_de_eq_d_times_64
    ld hl, (L74d0_target_object_climb_coordinates + 4)
    xor a
    sbc hl, de
    ; if (L74d0_target_object_climb_coordinates + 4) < object z * 64, skip
    jp m, La9c7_next_object

    ld h, (ix + OBJECT_SIZE_Z)
    call La9de_hl_eq_h_times_64
    add hl, de
    ld de, (L74d0_target_object_climb_coordinates + 4)
    xor a
    sbc hl, de
    ; if object z2 * 64 < (L74d0_target_object_climb_coordinates + 4), skip
    jp m, La9c7_next_object

    ; Collision!
    pop hl  ; simulate a ret
    jp La952  ; return from La929_teleport_player_if_no_collision
La9c7_next_object:
    ld e, (ix + OBJECT_SIZE)
    ld d, 0
    add ix, de  ; next object
    dec b
    jp nz, La954_object_loop
    ret


; --------------------------------
; input:
; - d
; output:
; - de = d * 64
La9d3_de_eq_d_times_64:
    ld e, 0
    srl d
    rr e
    srl d
    rr e
    ret


; --------------------------------
; input:
; - h
; output:
; - hl = h * 64
La9de_hl_eq_h_times_64:
    ld l, 0
    srl h
    rr l
    srl h
    rr l
    ret


; --------------------------------
; Calculates the Manhattan distance between the current player coordinates and (hl, de, bc)
; Input:
; - hl: x
; - de: y
; - bc: z
; Output:
; - hl = |hl - (L6aad_player_current_x)| + |de - (L6aaf_player_current_y)| + |(L6ab1_player_current_z) - bc|
La9e9_manhattan_distance_to_player:
    push bc
        ld bc, (L6aad_player_current_x)
        call Laa04_abs_hl_minus_bc
        ex de, hl
            ld bc, (L6aaf_player_current_y)
            call Laa04_abs_hl_minus_bc
            add hl, de
        ex de, hl
    pop bc
    ld hl, (L6ab1_player_current_z)
    call Laa04_abs_hl_minus_bc
    add hl, de  ; hl =  |hl - (L6aad_player_current_x)| + |de - (L6aaf_player_current_y)| + |(L6ab1_player_current_z) - bc|
    ret


; --------------------------------
; Returns the absolute value of "hl - bc"
; Input:
; - hl
; - bc
; Output:
; - hl
Laa04_abs_hl_minus_bc:
    or a
    sbc hl, bc  ; hl -= bc
    ret p  ; if positive, we are done
    ld a, h
    cpl
    ld h, a
    ld a, l
    cpl
    ld l, a
    inc hl
    ret


; --------------------------------
; Check if the correct coordinates due to cropping the player movement after colliding with an object
; are a better movement target than L74ca_movement_target_coordinates_2. If they are,
; overwrite the target coordinates. 
; - This method is always called from "Lab6d_correct_player_movement_if_collision_internal". If the correction is applied, this method will
;   directly return from the caller of the caller of "Lab6d_correct_player_movement_if_collision_internal".
Laa10_coordiante_corrected_movement_if_better:
    ld hl, (L74b8_collision_corrected_coordinates_2)
    ld de, (L74b8_collision_corrected_coordinates_2 + 2)
    ld bc, (L74b8_collision_corrected_coordinates_2 + 4)  ; hl, de, bc <- x, y, z
    call La9e9_manhattan_distance_to_player
    push hl
        ld hl, (L74ca_movement_target_coordinates_2)
        ld de, (L74ca_movement_target_coordinates_2 + 2)
        ld bc, (L74ca_movement_target_coordinates_2 + 4)
        call La9e9_manhattan_distance_to_player
    pop de
    ; At this point:
    ; - hl = distance from player to (L74b8_collision_corrected_coordinates_2)
    ; - de = distance from player to (L74ca_movement_target_coordinates_2)
    or a
    sbc hl, de
    jp m, Laa9e_return  ; if player is closer to (L74b8_collision_corrected_coordinates_2), return.
    push af
        ld d, 2  ; indicates colliding with a 3d shape
        ld a, (ix + OBJECT_TYPE_AND_FLAGS)
        and #0f
        cp OBJECT_TYPE_RECTANGLE
        jr z, Laa46
        cp OBJECT_TYPE_LINE
        jr nc, Laa46
        ld d, 1  ; indicates colliding with a 2d shape
Laa46:
    pop af
    jr nz, Laa63
    ; player is same distance from (L74b8_collision_corrected_coordinates_2) than from (L74ca_movement_target_coordinates_2).
    ld a, (L74e5_collision_correction_object_shape_type)
    or a
    jr z, Laa63
    cp d
    jr z, Laa56
    jr nc, Laa9e_return  ; Give preference to collisions with 3d shapes
    jr Laa63
Laa56:
    ld bc, (L74be_collision_corrected_climb_coordinates + 2)
    ld hl, (L74d0_target_object_climb_coordinates + 2)
    or a
    sbc hl, bc
    jp p, Laa9e_return  ; if this would prevent a climb, stop.
Laa63:
    ld a, d
    ld (L74e5_collision_correction_object_shape_type), a  ; 1 for 2d shapes, 2 for 3d shape collisions.
    ld a, (ix + OBJECT_ID)
    ld (L7480_under_pointer_object_ID), a
    ld a, 1
    ld (L7476_trigger_collision_event_flag), a
    ; Successful coordinate adjustment, update target coordinates:
    ld hl, L74be_collision_corrected_climb_coordinates
    ld de, L74d0_target_object_climb_coordinates
    ld bc, 6
    ldir

    ld hl, L74c4_collision_corrected_coordinates_1
    ld de, L74d6_movement_target_coordinates_1
    ld c, 6
    ldir

    ld hl, L74b8_collision_corrected_coordinates_2
    ld de, L74ca_movement_target_coordinates_2
    ld c, 6
    ldir

    ld a, (L6b28_player_radius)
    or a
    jr nz, Laa9e_return
    ; Unreachable in this game, as (L6b28_player_radius) is always 10.
    pop hl  ; ret from this function
    pop hl  ; undo push af from Lab6d_correct_player_movement_if_collision_internal
    pop hl  ; ret from this Lab6d_correct_player_movement_if_collision_internal
    pop hl  ; ret from this Lab56_correct_player_movement_if_collision
    jp La923_pop_and_return  ; return from La5d9_move_player
Laa9e_return:
    ret


; --------------------------------
; Finds the closest object below the player (using coordinates in "L74dc_falling_reference_coordinates"):
; - It stores the result in:
;   - L74e9_closest_object_below_ptr: pointer to object
;   - L74eb_closest_object_below_ID: ID of object
;   - L74e7_closest_object_below_distance: distance to object.
Laa9f_find_closest_object_below:
    ld hl, (L74dc_falling_reference_coordinates + 2)  ; player desired y
    ld (L74e7_closest_object_below_distance), hl  ; initialize (L74e7_closest_object_below_distance) to player desired y (distance to floor).
    xor a
    ld (L74eb_closest_object_below_ID), a  ; initialize found object ID to = 0
    ld ix, (L6ad1_current_area_objects)
    ld a, (L6ad0_current_area_n_objects)
    ld b, a
    or a
    call nz, Laac2_find_closest_object_below_internal
    ld ix, (L7463_global_area_objects)
    ld a, (L7465_global_area_n_objects)
    ld b, a
    or a
    call nz, Laac2_find_closest_object_below_internal
    ret


; --------------------------------
; Finds the closest object below the player (using coordinates in "L74dc_falling_reference_coordinates"):
; - It stores the result in:
;   - L74e9_closest_object_below_ptr: pointer to object
;   - L74eb_closest_object_below_ID: ID of object
;   - L74e7_closest_object_below_distance: distance to object.
; Input:
; - ix: pointer to the first object.
; - b: number of objects.
Laac2_find_closest_object_below_internal:
Laac2_find_closest_object_below_internal_object_loop:    
    push bc
        bit 6, (ix)  ; If object not visible, skip
        jp nz, Lab49_next_object
        ; Object is visible:
        ld hl, (L74dc_falling_reference_coordinates + 2)  ; current desired y
        ld a, (ix + OBJECT_Y)
        add a, (ix + OBJECT_SIZE_Y)
        ld d, a  ; d = object y2 = object y + object size y
        call La9d3_de_eq_d_times_64  ; de = object y2 * 64
        xor a
        sbc hl, de  ; hl = y - object y2 * 64
        ld b, h
        ld c, l  ; bc = y - object y2 * 64
        jp m, Lab49_next_object  ; if "y" smaller than object y2, skip

        ; Check if player desired x collides with object in "x" axis:
        ld h, (ix + OBJECT_X)
        call La9de_hl_eq_h_times_64
        ld de, (L74dc_falling_reference_coordinates)  ; player desired x
        or a
        sbc hl, de  ; hl = object x * 64 - player desired x
        ; if player x < object x, skip 
        jr z, Laaf1
        jp p, Lab49_next_object
Laaf1:
        ld a, (ix + OBJECT_X)
        add a, (ix + OBJECT_SIZE_X)
        ld h, a
        call La9de_hl_eq_h_times_64
        xor a
        sbc hl, de  ; hl = object x2 - player x
        ; if player x > object x2, skip
        jp m, Lab49_next_object

        ; Check if player desired x collides with object in "z" axis:
        ld h, (ix + OBJECT_Z)
        call La9de_hl_eq_h_times_64
        ld de, (L74dc_falling_reference_coordinates + 4)  ; player desired z
        or a
        sbc hl, de
        ; if player z < object z, skip 
        jr z, Lab13
        jp p, Lab49_next_object
Lab13:
        ld a, (ix + OBJECT_Z)
        add a, (ix + OBJECT_SIZE_Z)
        ld h, a
        call La9de_hl_eq_h_times_64
        or a
        sbc hl, de
        ; if player z > object z2, skip
        jp m, Lab49_next_object

        ; We found an object below the player:
        ; bc: distance from player to object in "y" axis
        ld hl, (L74e7_closest_object_below_distance)
        or a
        sbc hl, bc
        ; If the new object is further than the previous one we found, skip:
        jp m, Lab49_next_object
        ld (L74e7_closest_object_below_distance), bc  ; new closest distance in "y"
        ; If it's strictly closer than the previous one, record it:
        jr nz, Lab3f_new_best
        ; If it's the same distance as a previous object, prefer flat objects:
        ld a, (ix + OBJECT_TYPE_AND_FLAGS)
        and #0f
        cp OBJECT_TYPE_RECTANGLE
        jr z, Lab3f_new_best  ; flat rectangles are fine
        cp OBJECT_TYPE_LINE
        jr c, Lab49_next_object
Lab3f_new_best:
        ; If it is a rectangle, or another flat shape (line, triangle, etc.),
        ; we store the object pointer and ID:
        ld (L74e9_closest_object_below_ptr), ix
        ld a, (ix + OBJECT_ID)
        ld (L74eb_closest_object_below_ID), a

Lab49_next_object:
        ld e, (ix + OBJECT_SIZE)
        ld d, 0
        add ix, de
    pop bc
    dec b
    jp nz, Laac2_find_closest_object_below_internal_object_loop
    ret


; --------------------------------
; Adjusts player movement accounting for collisions:
; - see docstring of "Lab6d_correct_player_movement_if_collision_internal"
Lab56_correct_player_movement_if_collision:
    ld ix, (L6ad1_current_area_objects)
    ld a, (L6ad0_current_area_n_objects)
    or a
    call nz, Lab6d_correct_player_movement_if_collision_internal
    ld ix, (L7463_global_area_objects)
    ld a, (L7465_global_area_n_objects)
    or a
    call nz, Lab6d_correct_player_movement_if_collision_internal
    ret


; --------------------------------
; Adjusts player movement accounting for collisions:
; - Assuming the player wants to move to through the the volume (L74b2_movement_volume_min_coordinate) -> (L74ac_movement_volume_max_coordinate)
;   - this volume comprises the whole movement path, to make sure we do not skip small objects
;     with a large step.
;   - (L74b2_movement_volume_min_coordinate): (x2, y2, z2)   (max position + radius)
;   - (L74ac_movement_volume_max_coordinate): (x1, y1, z1)   (min position - radius)
; - If this new position causes a collision, adjust the position (based on the current movement
;   direction), to find a position that does not collide.
; - The result are updated positions for target movement (the 3 sets of possible target positions
;   are updated).
; - Note: this function is so convoluted, and there are solutions that are so much simpler than this!
;   On top of that, this method prevents "sliding" along walls, which is an expected
;   feature of modern engines. So, I would scrap all that special code.
;   As a consequence, I only annotated the first part, (x collision), as the other two parts
;   (y and z collision are analogous).
; Input:
; - ix: pointer to the first object
; - a: number of objects
Lab6d_correct_player_movement_if_collision_internal:
Lab6d_correct_player_movement_if_collision_internal_object_loop:
    push af
        bit 6, (ix)  ; check if object is visible
        jp nz, Lae6e_next_object ; If not visible, skip.

        ; 'x' axis comparison:
        ld h, (ix + OBJECT_X)
        call La9de_hl_eq_h_times_64
        ld de, (L74ac_movement_volume_max_coordinate)  ; x1
        or a
        sbc hl, de  ; hl = object x * 64 - x1
        jp p, Lae6e_next_object  ; if no x collision skip

        ld a, (ix + OBJECT_X)
        add a, (ix + OBJECT_SIZE_X)
        ld d, a
        call La9d3_de_eq_d_times_64
        ld hl, (L74b2_movement_volume_min_coordinate)  ; x2
        or a
        sbc hl, de
        jp p, Lae6e_next_object  ; if no x collision skip

        ; 'y' axis comparison:
        ld h, (ix + OBJECT_Y)
        call La9de_hl_eq_h_times_64
        ld de, (L74ac_movement_volume_max_coordinate + 2)  ; y1
        or a
        sbc hl, de
        jp p, Lae6e_next_object  ; if no y collision skip

        ld a, (ix + OBJECT_Y)
        add a, (ix + OBJECT_SIZE_Y)
        ld d, a
        call La9d3_de_eq_d_times_64
        ld hl, (L74b2_movement_volume_min_coordinate + 2)  ; y2
        or a
        sbc hl, de
        jp p, Lae6e_next_object  ; if no y collision skip

        ; 'z' axis comparison:
        ld h, (ix + OBJECT_Z)
        call La9de_hl_eq_h_times_64
        ld de, (L74ac_movement_volume_max_coordinate + 4)  ; z1
        or a
        sbc hl, de
        jp p, Lae6e_next_object  ; if no z collision skip

        ld a, (ix + OBJECT_Z)
        add a, (ix + OBJECT_SIZE_Z)
        ld d, a
        call La9d3_de_eq_d_times_64
        ld hl, (L74b2_movement_volume_min_coordinate + 4)  ; z2
        or a
        sbc hl, de
        jp p, Lae6e_next_object  ; if no z collision skip

        ; Object and the volume defined by (L74b2_movement_volume_min_coordinate) -> (L74ac_movement_volume_max_coordinate) collide! 
        ld de, (L6b28_player_radius)
        ld a, (L74e2_movement_direction_bits)
        bit 0, a  ; negative movement on x?
        jr z, Labf2
        ; negative movement on x:
        ld a, (ix + OBJECT_X)
        add a, (ix + OBJECT_SIZE_X)
        ld h, a
        jr Lac02
Labf2:
        bit 1, a  ; positive movement on x?
        jp z, Lacbd_y_coordinate_adjust

        ; positive movement on x:
        ld h, (ix + OBJECT_X)
        ; negate the sign of the radius:
        ld a, e
        neg
        jr z, Lac02
        ld e, a
        ld d, #ff  ; de = - player_radius
Lac02:
        ; At this point:
        ; - h = object bound with whith player collided
        ; - de = amount to add to the bound due to player radius
        call La9de_hl_eq_h_times_64  ; hl = bound * 64
        add hl, de  ; hl = bound * 64 + radius
        ld (L74b8_collision_corrected_coordinates_2), hl  ; limit up to which we can move in x
        ex de, hl
        ld hl, (L74b2_movement_volume_min_coordinate)  ; x2
        or a
        sbc hl, de  ; amount we need to correct the movement (should be negative).
        jp p, Lacbd_y_coordinate_adjust  ; if it is not negative, something weird has happend, and just ignore.
        ld hl, (L74ac_movement_volume_max_coordinate)  ; x1
        or a
        sbc hl, de  ; make sure we would not move out of bounds
        jp m, Lacbd_y_coordinate_adjust  ; if we are out of bounds, ignore
        ex de, hl  ; hl = limit up to which we can move in x
        call Lae7b_relative_z_proportional_to_relative_x_and_player_movement_direction
        ld (L74b8_collision_corrected_coordinates_2 + 4), hl  ; limit z movement proportionally
        ld (L74be_collision_corrected_climb_coordinates + 4), hl
        ld (L74c4_collision_corrected_coordinates_1 + 4), hl
        ld d, (ix + OBJECT_Z)
        call La9d3_de_eq_d_times_64
        ld bc, (L6b28_player_radius)
        ex de, hl
        or a
        sbc hl, bc  ; hl = object z * 64 - player radius
        ex de, hl
        or a
        sbc hl, de  ; hl = new z - object z * 64 - player radius
        ld a, (L74e2_movement_direction_bits)
        jp p, Lac49  ; if this does not result in positive movement in z, we keep going
        ; negative z movement as a result of the adjustment:
        bit 4, a  ; negative movement in z?
        jp nz, Lae6e_next_object  ; if we moved negatively in z, ignore this object's collision
        jp Lacbd_y_coordinate_adjust
Lac49:
        ; here:
        ; - de = object z * 64 - player radius
        ; - bc = player radius
        ld h, (ix + OBJECT_SIZE_Z)
        call La9de_hl_eq_h_times_64
        add hl, de
        add hl, bc
        add hl, bc  ; hl = object z2 * 64 + player radius
        ex de, hl
        ld hl, (L74b8_collision_corrected_coordinates_2 + 4)  ; new z we wanted as a result of x collision
        or a
        sbc hl, de  ; hl = new z - (object z2 * 64 + player radius)
        jp m, Lac64  ; this would cause a collision
        bit 5, a  ; positive movement in z?
        jp nz, Lae6e_next_object  ; if we moved positively in z, ignore this object's collision
        jp Lacbd_y_coordinate_adjust
Lac64:
        call Laeb1_adjust_y_movement_relative_to_x_movement_limit_due_to_collision
        ld a, (L74e2_movement_direction_bits)
        jp p, Lac74
        bit 2, a  ; negative movement in y?
        jp nz, Lae6e_next_object
        jr Lacbd_y_coordinate_adjust
Lac74:
        ld h, (ix + OBJECT_SIZE_Y)
        call La9de_hl_eq_h_times_64
        add hl, de
        ex de, hl
        ld hl, (L74b8_collision_corrected_coordinates_2 + 2)  ; new adjusted y
        or a
        sbc hl, de
        jp m, Lac8c
        bit 3, a
        jp nz, Lae6e_next_object
        jr Lacbd_y_coordinate_adjust
Lac8c:
        ld a, (ix + OBJECT_Y)
        add a, (ix + OBJECT_SIZE_Y)
        ld h, a
        call La9de_hl_eq_h_times_64
        ld (L74be_collision_corrected_climb_coordinates + 2), hl
        ld hl, (L74b8_collision_corrected_coordinates_2)
        ld bc, (L6b28_player_radius)
        inc bc
        or a
        sbc hl, bc
        ld e, l
        ld d, h
        add hl, bc
        add hl, bc
        ld a, (L74e2_movement_direction_bits)
        bit 0, a  ; negative movement in x?
        jr nz, Lacb0
        ex de, hl  ; flip the coordinates
Lacb0:
        ld (L74be_collision_corrected_climb_coordinates), de
        ld (L74c4_collision_corrected_coordinates_1), hl
        call Laa10_coordiante_corrected_movement_if_better
        jp Lae6e_next_object

Lacbd_y_coordinate_adjust:
        ld de, (L6b28_player_radius)
        ld a, (L74e2_movement_direction_bits)
        bit 2, a
        jr z, Lacd1
        ld a, (ix + 2)
        add a, (ix + 5)
        ld h, a
        jr Lace1
Lacd1:
        bit 3, a
        jp z, Ladb6
        ld h, (ix + 2)
        ld a, e
        neg
        jr z, Lace1
        ld e, a
        ld d, 255
Lace1:
        call La9de_hl_eq_h_times_64
        add hl, de
        ld (L74b8_collision_corrected_coordinates_2 + 2), hl
        ex de, hl
        ld hl, (L74b2_movement_volume_min_coordinate + 2)
        or a
        sbc hl, de
        jp p, Ladb6
        ld hl, (L74ac_movement_volume_max_coordinate + 2)
        or a
        sbc hl, de
        jp m, Ladb6
        ex de, hl
        ld de, (L6aaf_player_current_y)
        xor a
        sbc hl, de
        ld de, (L74a6_player_movement_delta + 4)
        call La15e_de_times_hl_signed
        ld bc, (L74a6_player_movement_delta + 2)
        call Lb1b7_de_hl_divided_by_bc_signed
        ld bc, (L6ab1_player_current_z)
        add hl, bc
        ld (L74b8_collision_corrected_coordinates_2 + 4), hl
        ld (L74c4_collision_corrected_coordinates_1 + 4), hl
        ld d, (ix + 3)
        call La9d3_de_eq_d_times_64
        ld bc, (L6b28_player_radius)
        ex de, hl
        or a
        sbc hl, bc
        ex de, hl
        or a
        sbc hl, de
        ld a, (L74e2_movement_direction_bits)
        jp p, Lad3c
        bit 4, a
        jp nz, Lae6e_next_object
        jp Ladb6
Lad3c:
        ld h, (ix + 6)
        call La9de_hl_eq_h_times_64
        add hl, de
        add hl, bc
        add hl, bc
        ex de, hl
        ld hl, (L74b8_collision_corrected_coordinates_2 + 4)
        or a
        sbc hl, de
        jp m, Lad57
        bit 5, a
        jp nz, Lae6e_next_object
        jp Ladb6
Lad57:
        ld hl, (L74b8_collision_corrected_coordinates_2 + 4)
        call Lae96_relative_x_proportional_to_relative_z_and_player_movement_direction
        ld (L74b8_collision_corrected_coordinates_2), hl
        ld (L74c4_collision_corrected_coordinates_1), hl
        ld d, (ix + 1)
        call La9d3_de_eq_d_times_64
        ld bc, (L6b28_player_radius)
        ex de, hl
        or a
        sbc hl, bc
        ex de, hl
        or a
        sbc hl, de
        ld a, (L74e2_movement_direction_bits)
        jp p, Lad82
        bit 0, a
        jp nz, Lae6e_next_object
        jr Ladb6
Lad82:
        ld h, (ix + 4)
        call La9de_hl_eq_h_times_64
        add hl, de
        add hl, bc
        add hl, bc
        ex de, hl
        ld hl, (L74b8_collision_corrected_coordinates_2)
        or a
        sbc hl, de
        jp m, Lad9c
        bit 1, a
        jp nz, Lae6e_next_object
        jr Ladb6
Lad9c:
        ld de, (L6b28_player_radius)
        ld hl, (L74b8_collision_corrected_coordinates_2 + 2)
        bit 2, a
        jr z, Ladaa
        add hl, de
        jr Ladad
Ladaa:
        or a
        sbc hl, de
Ladad:
        ld (L74c4_collision_corrected_coordinates_1 + 2), hl
        call Laa10_coordiante_corrected_movement_if_better
        jp Lae6e_next_object
Ladb6:
        ld de, (L6b28_player_radius)
        ld a, (L74e2_movement_direction_bits)
        bit 4, a
        jr z, Ladca
        ld a, (ix + 3)
        add a, (ix + 6)
        ld h, a
        jr Ladda
Ladca:
        bit 5, a
        jp z, Lae6e_next_object
        ld h, (ix + 3)
        ld a, e
        neg
        jr z, Ladda
        ld e, a
        ld d, 255
Ladda:
        call La9de_hl_eq_h_times_64
        add hl, de
        ld (L74b8_collision_corrected_coordinates_2 + 4), hl
        ex de, hl
        ld hl, (L74b2_movement_volume_min_coordinate + 4)
        or a
        sbc hl, de
        jp p, Lae6e_next_object
        ld hl, (L74ac_movement_volume_max_coordinate + 4)
        or a
        sbc hl, de
        jp m, Lae6e_next_object
        ex de, hl
        call Lae96_relative_x_proportional_to_relative_z_and_player_movement_direction
        ld (L74b8_collision_corrected_coordinates_2), hl
        ld (L74be_collision_corrected_climb_coordinates), hl
        ld (L74c4_collision_corrected_coordinates_1), hl
        ld d, (ix + 1)
        call La9d3_de_eq_d_times_64
        ld bc, (L6b28_player_radius)
        ex de, hl
        or a
        sbc hl, bc
        ex de, hl
        or a
        sbc hl, de
        jp m, Lae6e_next_object
        ld h, (ix + 4)
        call La9de_hl_eq_h_times_64
        add hl, de
        add hl, bc
        add hl, bc
        ex de, hl
        ld hl, (L74b8_collision_corrected_coordinates_2)
        or a
        sbc hl, de
        jp p, Lae6e_next_object
        call Laeb1_adjust_y_movement_relative_to_x_movement_limit_due_to_collision
        jp m, Lae6e_next_object
        ld h, (ix + 5)
        call La9de_hl_eq_h_times_64
        add hl, de
        ex de, hl
        ld hl, (L74b8_collision_corrected_coordinates_2 + 2)
        or a
        sbc hl, de
        jp p, Lae6e_next_object
        ld a, (ix + 2)
        add a, (ix + 5)
        ld h, a
        call La9de_hl_eq_h_times_64
        ld (L74be_collision_corrected_climb_coordinates + 2), hl
        ld hl, (L74b8_collision_corrected_coordinates_2 + 4)
        ld bc, (L6b28_player_radius)
        inc bc
        or a
        sbc hl, bc
        ld e, l
        ld d, h
        add hl, bc
        add hl, bc
        ld a, (L74e2_movement_direction_bits)
        bit 4, a
        jr nz, Lae64
        ex de, hl
Lae64:
        ld (L74be_collision_corrected_climb_coordinates + 4), de
        ld (L74c4_collision_corrected_coordinates_1 + 4), hl
        call Laa10_coordiante_corrected_movement_if_better
Lae6e_next_object:
        ; Advance the pointer to the next object:
        ld e, (ix + OBJECT_SIZE)
        ld d, 0
        add ix, de
    pop af
    dec a
    jp nz, Lab6d_correct_player_movement_if_collision_internal_object_loop
    ret


; --------------------------------
; Given a "x" coordinate, it calculates a "z" such that (player z - z) is proportional to (player x - x) according
; to the current movement direction of the player.
; Input:
; - hl: x coordinate
; Output:
; - hl: (hl - player x) * (delta z / delta x) + player z
Lae7b_relative_z_proportional_to_relative_x_and_player_movement_direction:
    ld de, (L6aad_player_current_x)
    xor a
    sbc hl, de  ; hl -= player x
    ld de, (L74a6_player_movement_delta + 4)
    call La15e_de_times_hl_signed  ; hl = (hl - player x) * delta z
    ld bc, (L74a6_player_movement_delta)
    call Lb1b7_de_hl_divided_by_bc_signed  ; hl = ((hl - player x) * delta z) / delta x
    ld bc, (L6ab1_player_current_z)
    add hl, bc  ; hl = (hl - player x) * (delta z / delta x) + player z
    ret


; --------------------------------
; Given a "z" coordinate, it calculates a "x" such that (player x - x) is proportional to (player z - z) according
; to the current movement direction of the player.
; Input:
; - hl: z coordinate
; Output:
; - hl: (hl - player z) * (delta x / delta z) + player x
Lae96_relative_x_proportional_to_relative_z_and_player_movement_direction:
    ld de, (L6ab1_player_current_z)
    xor a
    sbc hl, de  ; hl -= player z
    ld de, (L74a6_player_movement_delta)
    call La15e_de_times_hl_signed  ; hl = (hl - player z) * delta x
    ld bc, (L74a6_player_movement_delta + 4)
    call Lb1b7_de_hl_divided_by_bc_signed  ; hl = ((hl - player z) * delta x) / delta z
    ld bc, (L6aad_player_current_x)  ; hl = (hl - player z) * (delta x / delta z) + player x
    add hl, bc
    ret


; --------------------------------
; Output:
; - hl: (actual delta x) * (delta y) / (delta x) + player y + (L74e3_player_height_16bits) - object y
;       This is used by the caller to see if this would result in a collision in y.
Laeb1_adjust_y_movement_relative_to_x_movement_limit_due_to_collision:
    ld hl, (L74b8_collision_corrected_coordinates_2)  ; limit up to which we can move in x
    ld de, (L6aad_player_current_x)
    xor a
    sbc hl, de  ; hl = actual delta x = amount of movement allowed in x due to collision
    ld de, (L74a6_player_movement_delta + 2)  ; delta y
    call La15e_de_times_hl_signed  ; (de, hl) = (actual delta x) * delta y
    ld bc, (L74a6_player_movement_delta)
    call Lb1b7_de_hl_divided_by_bc_signed  ; (de, hl) = (actual delta x) * (delta y) / (delta x)
    ld bc, (L6aaf_player_current_y)
    add hl, bc  ; (de, hl) = ((L74b8_collision_corrected_coordinates_2) - player x) * (delta y) / (delta x) + player y
    ld (L74b8_collision_corrected_coordinates_2 + 2), hl  ; adjust new target y, proportionally to how much did we cut movement on x
    ld (L74c4_collision_corrected_coordinates_1 + 2), hl
    ld d, (ix + OBJECT_Y)
    call La9d3_de_eq_d_times_64
    ld bc, (L74e3_player_height_16bits)
    or a
    adc hl, bc  ; hl = (actual delta x) * (delta y) / (delta x) + player y + (L74e3_player_height_16bits)
    or a
    sbc hl, de  ; hl = (actual delta x) * (delta y) / (delta x) + player y + (L74e3_player_height_16bits) - object y
    ret


; --------------------------------
; Processes the following input key functions:
; - INPUT_CRAWL
; - INPUT_WALK
; - INPUT_RUN
; - INPUT_FORWARD
; - INPUT_BACKWARD
; - INPUT_TURN_LEFT
; - INPUT_TURN_RIGHT
; - INPUT_LOOK_UP
; - INPUT_LOOK_DOWN
; - INPUT_FACE_FORWARD
; - INPUT_U_TURN
Laee5_executes_movement_related_pressed_key_functions:
    ld bc, 0
    ld hl, L6d89_text_crawl
    cp INPUT_CRAWL
    jr z, Laf00_desired_walk_speed_selected
    ld hl, L6d99_text_walk
    inc c
    cp INPUT_WALK
    jr z, Laf00_desired_walk_speed_selected
    ld hl, L6da9_text_run
    inc c
    cp INPUT_RUN
    jp nz, Lafda
Laf00_desired_walk_speed_selected:
    ld a, (L6b0b_selected_movement_mode)
    cp c
    jr nz, Laf00_walk_speed_change_needed
    ld c, 0
    jp Lafc1_already_at_correct_walk_speed
Laf00_walk_speed_change_needed:
    ld d, a
    ld hl, L6d79_text_too_weak
    ld a, (L6b0a_current_strength)
    cp 3
    jr nc, Lafc1_strength_at_least_3
    ld a, c
    or a
    jr z, Laf25_strength_at_least_5
    jr Laf65_cannot_change_to_requested_speed
Lafc1_strength_at_least_3:
    cp 5
    jr nc, Laf25_strength_at_least_5
    ld a, c
    cp 2
    jr z, Laf65_cannot_change_to_requested_speed
Laf25_strength_at_least_5:
    ; We have the required strength for the requested walk speed:
    ; here: d = current walk speed, c = requested walk speed.
    ld a, d
    or a
    jr nz, Laf75_speed_change_is_possible

    ; Current speed is "crawling", requested to stand up, check if we have space:
    ld hl, (L6aad_player_current_x)
    ld (L7456_player_desired_x), hl
    ld hl, (L6ab1_player_current_z)
    ld (L745a_player_desired_z), hl
    ld a, (L6abc_current_room_scale)
    ld e, b  ; b == 0 here
    ld d, a
    srl d
    rr e
    srl d
    rr e  ; de = (L6abc_current_room_scale) * 64

    ld hl, (L6aaf_player_current_y)
    push hl
        add hl, de  ; player y + room_scale * 64
        ld (L7458_player_desired_y), hl
        ld a, 1
        ld (L6abe_use_eye_player_coordinate), a
        call La5d9_move_player
        xor a
        ld (L6abe_use_eye_player_coordinate), a
        ld de, (L7458_player_desired_y)
        sbc hl, de
    pop hl
    jr z, Laf69_getting_up_is_possible
    ; We do not have enough room to get up:
    ld (L6aaf_player_current_y), hl
    ld hl, L6d69_text_not_enough_room
Laf65_cannot_change_to_requested_speed:
    ld c, 0
    jr Lafc1_already_at_correct_walk_speed
Laf69_getting_up_is_possible:
    ; Get up from crawling:
    ld hl, L6ab8_player_crawling
    inc (hl)
    ld hl, L6ab9_player_height
    ld a, (L6abc_current_room_scale)
    add a, (hl)
    ld (hl), a

Laf75_speed_change_is_possible:
    ld a, c
    ld (L6b0b_selected_movement_mode), a
    ld hl, L6d99_text_walk
    cp 1
    jr z, Lafaa
    ld hl, L6da9_text_run
    or a
    jr nz, Lafaa
    ; Switch to crawling, we need to crouch:
    ld hl, L6ab8_player_crawling
    dec (hl)
    ld hl, L6ab9_player_height
    ld a, (L6abc_current_room_scale)
    ld d, a
    sub (hl)
    neg
    ld (hl), a

    ; de = (L6abc_current_room_scale) * 64
    ld e, c  ; c == 0 here
    srl d
    rr e
    srl d
    rr e
    ld hl, (L6aaf_player_current_y)
    or a
    sbc hl, de
    ld (L6aaf_player_current_y), hl
    ld hl, L6d89_text_crawl
Lafaa:
    ex de, hl
        ld hl, Ld0c8_speed_when_crawling
        add hl, bc
        ld a, (hl)
        ld (L6ab5_current_speed), a
        ld l, a
        ld h, b
        ld a, (L6abc_current_room_scale)
        call La108_a_times_hl_signed
        ld (L6ab3_current_speed_in_this_room), hl
    ex de, hl
    ld c, 20
Lafc1_already_at_correct_walk_speed:
    ; Print the walk speed message, produce an SFX, and set a delay the message to disappear.
    ld a, 42
    ld (L74a5_interrupt_timer), a
    ld ix, L735a_ui_message_row_pointers
    ld de, #0f00
    call Ld01c_draw_string
    ld a, SFX_MENU_SELECT
    call Lc4ca_play_SFX
    ld b, #20  ; set the 6th bit of (L746c_game_flags + 1), which will trigger rewriting the "THE CRYPT" message after a pause
    jp Lb191_done

Lafda:
    ld c, 0
    cp INPUT_FORWARD
    jr z, Lafe5
    cp INPUT_BACKWARD
    jp nz, Lb0a5
Lafe5:
    push af
        ld hl, (L6ab3_current_speed_in_this_room)
        cp INPUT_BACKWARD
        jr nz, Lb000_move
        ; Either backwards or forward+backwards keys pressed simultaneously:
        ld a, (L6b0b_selected_movement_mode)
        cp 2
        jr nz, Lb000_move
        ; Slow down running to walk speed, since we are pressing backwards:
        ld a, (Ld0c9_speed_when_walking)
        ld l, a
        ld h, 0
        ld a, (L6abc_current_room_scale)
        call La108_a_times_hl_signed
Lb000_move:
        push hl
            ld a, (L6ab7_player_yaw_angle)
            ; update in "z":
            ld ix, L73c6_cosine_sine_table
            ld e, a
            ld d, c
            add ix, de
            add ix, de
            ld a, (ix + 1)  ; cos(yaw)
            call La108_a_times_hl_signed
            sla l
            rl h
            rl a
            sla l
            rl h
            rl a
            ld l, h
            ld h, a
            ; hl = (cos(yaw) * movement speed) / 1024
        pop de
    pop af
    push af
        push de
            ld d, 9  ; eye ui frame
            cp INPUT_FORWARD
            jr z, Lb034
            ; We are moving backwaards:
            ; hl = -hl
            ld a, h
            cpl
            ld h, a
            ld a, l
            cpl
            ld l, a
            inc hl
            inc d  ; change eye ui frame
Lb034:
            call Lb1a0_draw_compass_eye_ui_frame
            ld de, (L6ab1_player_current_z)
            add hl, de
            ld (L745a_player_desired_z), hl
        pop hl
        ; update in "x":
        ld a, (ix)  ; sin(yaw)
        call La108_a_times_hl_signed
        sla l
        rl h
        rl a
        sla l
        rl h
        rl a
        ld l, h
        ld h, a
        ; hl = (sin(yaw) * movement speed) / 1024
    pop af
    cp INPUT_FORWARD
    jr z, Lb060
    ; We are moving backwards:
    ; hl = -hl
    ld a, h
    cpl
    ld h, a
    ld a, l
    cpl
    ld l, a
    inc hl
Lb060:
    ld de, (L6aad_player_current_x)
    add hl, de
    ld (L7456_player_desired_x), hl
    ; update in "y":
    ld hl, (L6aaf_player_current_y)
    ld (L7458_player_desired_y), hl
    ld a, (L6abe_use_eye_player_coordinate)
    or a
    jr nz, Lb08c_no_y_adjustment
    ; subtract player height from player y (this is used in the codebase to,
    ; move from "eye" coordinate, to "feet" coordinates.)
    ld a, (L6ab9_player_height)
    dec a
    ld d, a
    ld e, 128
    srl d
    rr e
    srl d
    rr e    ; de = ((L6ab9_player_height) - 1) * 64 + 32
    or a
    sbc hl, de
    ld (L6aaf_player_current_y), hl
    ld (L7458_player_desired_y), hl

Lb08c_no_y_adjustment:
    call La5d9_move_player
    or a
    jr z, Lb095
    ld bc, #34  ; Add flags to L746c_game_flags
Lb095:
    ld a, (L6abe_use_eye_player_coordinate)
    or a
    jr nz, Lb0a2_no_y_adjustment
    ; If we had moved coordinates from eye to feet, bring back player y, to "eye" coordinates:
    ld hl, (L6aaf_player_current_y)
    add hl, de
    ld (L6aaf_player_current_y), hl
Lb0a2_no_y_adjustment:
    jp Lb18c_done_setting_L747f_player_event_to_1

Lb0a5:
    cp INPUT_TURN_LEFT
    jr nz, Lb0bd
    ld hl, L6ab7_player_yaw_angle
    ld bc, #24  ; Add flags to L746c_game_flags
    ; Determine rotation speed: if shift is pressed, rotate 90 degrees
    ld a, (L7472_symbol_shift_pressed)
    or a
    ld a, FULL_ROTATION_DEGREES / 4
    jr nz, Lb0ba
    ld a, (Ld0ce_yaw_rotation_speed)
Lb0ba:
    jp Lb168_turn_left
Lb0bd:
    cp INPUT_TURN_RIGHT
    jr nz, Lb0d5_no_turn_right
    ld hl, L6ab7_player_yaw_angle
    ld bc, #24  ; Add flags to L746c_game_flags
    ; Determine rotation speed: if shift is pressed, rotate 90 degrees
    ld a, (L7472_symbol_shift_pressed)
    or a
    ld a, FULL_ROTATION_DEGREES / 4
    jr nz, Lb0d2
    ld a, (Ld0ce_yaw_rotation_speed)
Lb0d2:
    jp Lb15b_turn_right

Lb0d5_no_turn_right:
    cp INPUT_FACE_FORWARD
    jr nz, Lb104_no_face_forward
    ld a, (L6ab6_player_pitch_angle)
    or a
    jp z, Lb18c_done_setting_L747f_player_event_to_1
    ; "face forward" UI eye animation:
    ld ix, L7350_compass_eye_ui_row_pointers
    ld hl, L7792_ui_compass_eye_sprites
    ld de, #0400  ; Start with frame 4
Lb0ea_face_forward_animation_loop:
    inc d
    call Lc895_draw_sprite_to_ix_ptrs
    ld a, 2
    ld (L74a5_interrupt_timer), a
Lb0f3_pause_loop:
    ld a, (L74a5_interrupt_timer)
    or a
    jr nz, Lb0f3_pause_loop
    ld a, 8
    cp d
    jr nz, Lb0ea_face_forward_animation_loop

    ld (L6b2b_desired_eye_compass_frame), a
    xor a
    jr Lb152_desired_pitch_set

Lb104_no_face_forward:
    cp INPUT_LOOK_UP
    jr nz, Lb12b
    ld d, 1  ; desired ui eye frame
    call Lb1a0_draw_compass_eye_ui_frame
    ; If shift is pressed, go directly to -18 (54) degrees
    ld a, (L7472_symbol_shift_pressed)
    or a
    jr nz, Lb127
    ld a, (Ld0ce_yaw_rotation_speed)
    ld e, a
    ld a, (L6ab6_player_pitch_angle)
    sub e
    jr nc, Lb11f_no_overflow
    add a, FULL_ROTATION_DEGREES
Lb11f_no_overflow:
    cp FULL_ROTATION_DEGREES - FULL_ROTATION_DEGREES / 4
    jr nc, Lb152_desired_pitch_set
    cp FULL_ROTATION_DEGREES / 4
    jr c, Lb152_desired_pitch_set
Lb127:
    ld a, FULL_ROTATION_DEGREES - FULL_ROTATION_DEGREES / 4
    jr Lb152_desired_pitch_set

Lb12b:
    cp INPUT_LOOK_DOWN
    jr nz, Lb177
    ld d, 2  ; desired ui eye frame
    call Lb1a0_draw_compass_eye_ui_frame
    ; If shift is pressed, go directly to 18 degrees
    ld a, (L7472_symbol_shift_pressed)
    or a
    jr nz, Lb150
    ld a, (Ld0ce_yaw_rotation_speed)
    ld e, a
    ld a, (L6ab6_player_pitch_angle)
    add a, e
    cp FULL_ROTATION_DEGREES
    jr c, Lb148
    sub FULL_ROTATION_DEGREES
Lb148:
    cp FULL_ROTATION_DEGREES - FULL_ROTATION_DEGREES / 4
    jr nc, Lb152_desired_pitch_set
    cp FULL_ROTATION_DEGREES / 4
    jr c, Lb152_desired_pitch_set
Lb150:
    ld a, FULL_ROTATION_DEGREES / 4
Lb152_desired_pitch_set:
    ld (L6ab6_player_pitch_angle), a
    ld bc, #44  ; Add flags to L746c_game_flags
    jp Lb18c_done_setting_L747f_player_event_to_1

Lb15b_turn_right:
    ld e, a
    ld d, 4
    ld a, (hl)
    add a, e
    cp 72
    jr c, Lb171_no_overflow
    sub 72
    jr Lb171_no_overflow

Lb168_turn_left:
    ld e, a
    ld d, 3  ; eye ui frame
    ld a, (hl)
    sub e
    jr nc, Lb171_no_overflow
    add a, FULL_ROTATION_DEGREES
Lb171_no_overflow:
    ld (hl), a
    call Lb1a0_draw_compass_eye_ui_frame
    jr Lb18c_done_setting_L747f_player_event_to_1

Lb177:
    cp INPUT_U_TURN
    jr nz, Lb191_done
    ld bc, FULL_ROTATION_DEGREES / 2
    ld a, (L6ab7_player_yaw_angle)
    add a, FULL_ROTATION_DEGREES / 2
    cp FULL_ROTATION_DEGREES
    jr c, Lb189_no_overflow
    sub FULL_ROTATION_DEGREES
Lb189_no_overflow:
    ld (L6ab7_player_yaw_angle), a
Lb18c_done_setting_L747f_player_event_to_1:
    ld a, 1
    ld (L747f_player_event), a
Lb191_done:
    ld a, (L746c_game_flags)
    or c
    ld (L746c_game_flags), a
    ld a, (L746c_game_flags + 1)
    or b
    ld (L746c_game_flags + 1), a
    ret


; --------------------------------
; Draws a frame of the "compass eye" in the game UI.
; This visualization changes depending on the direction you are turning or moving.
; Input:
; - d: frame to draw
Lb1a0_draw_compass_eye_ui_frame:
    push ix
    push hl
        ld ix, L7350_compass_eye_ui_row_pointers  ; ptr to row pointers
        ld hl, L7792_ui_compass_eye_sprites  ; ptr to w, h, mask, size, data
        ld e, 0  ; x_offset
        call Lc895_draw_sprite_to_ix_ptrs
        xor a
        ld (L6b2b_desired_eye_compass_frame), a
    pop hl
    pop ix
    ret


; --------------------------------
; Signed division between (DE,HL) / BC.
; Result stored in (DE,HL), and remainder in BC
; Note: division result sometimes is off by 1
;       (maybe this is ok if these are fixed-point precision numbers with lower bits
;        dedicated to the fractionary part).
; Input:
; - de, hl
; - bc
; Output:
; - de, hl
; - bc
Lb1b7_de_hl_divided_by_bc_signed:
    push af
        ld a, h
        or l
        jr nz, Lb1c4
        ld a, d
        or e
        jr nz, Lb1c4
        ld b, a
        ld c, a
    pop af
    ret
Lb1c4:
        exx
        push hl
        push de
        push bc
            ld d, 0
            exx
            bit 7, d
            jr z, Lb1e4
            exx
            inc d
            exx
            ld a, d
            cpl
            ld d, a
            ld a, e
            cpl
            ld e, a
            ld a, h
            cpl
            ld h, a
            ld a, l
            cpl
            ld l, a
            inc hl
            ld a, h
            or l
            jr nz, Lb1e4
            inc de
Lb1e4:
            bit 7, b
            jr z, Lb1f5
            ld a, b
            cpl
            ld b, a
            ld a, c
            cpl
            ld c, a
            inc bc
            exx
            ld a, d
            xor 1
            ld d, a
            exx
Lb1f5:
            push bc
                exx
            pop bc
            ld hl, 0
            exx
            ld b, 32
Lb1fe:
            add hl, hl
            rl e
            rl d
            jr c, Lb20f
            djnz Lb1fe
            jr Lb250
Lb209:
            adc hl, hl
            rl e
            rl d
Lb20f:
            exx
            adc hl, hl
            sbc hl, bc
            jr nc, Lb217
            add hl, bc
Lb217:
            exx
            ccf
            djnz Lb209
            adc hl, hl
            rl e
            rl d
            exx
            push hl
                sra b
                rr c
                or a
                sbc hl, bc
                exx
            pop bc
            jp m, Lb235
            inc hl
            ld a, l
            or h
            jr nz, Lb235
            inc de
Lb235:
            exx
            bit 0, d
        pop bc
        pop de
        pop hl
        exx
        jr z, Lb250
        ld a, h
        cpl
        ld h, a
        ld a, l
        cpl
        ld l, a
        ld a, d
        cpl
        ld d, a
        ld a, e
        cpl
        ld e, a
        inc hl
        ld a, l
        or h
        jr nz, Lb250
        inc de
Lb250:
    pop af
    ret


; --------------------------------
; Set the screen area to a uniform attribute read from "L6add_desired_attribute_color", and sets the border to black.
Lb252_set_screen_area_attributes:
    push hl
    push de
    push bc
    push af
        xor a
        ld (L7466_need_attribute_refresh_flag), a  ; Mark that the border has already been set.
        ld hl, (L6adb_desired_border_color)  ; Desired border color (only msb used)
        ld (L6ad7_current_border_color), hl
        ld hl, (L6add_desired_attribute_color)  ; Desired attribute (only msb used)
        ld (L6ad9_current_attribute_color), hl
        ld hl, L5800_VIDEOMEM_ATTRIBUTES + 4 * 32 + 4
        ld a, (L6ad9_current_attribute_color)  ; read the color attribute
        ld de, 8  ; skip 4 rows to the right/left of the viewport
        ld c, SCREEN_HEIGHT
        ; Set the attributes of the whole game area to "a"
Lb271_row_loop:
        ld b, SCREEN_WIDTH
Lb273_column_loop:
        ld (hl), a
        inc hl
        djnz Lb273_column_loop
        add hl, de
        dec c
        jr nz, Lb271_row_loop
        xor a
        ld (L6ad7_current_border_color), a  ; Current border to 0
        out (ULA_PORT), a  ; black border, and no sound.
    pop af
    pop bc
    pop de
    pop hl
    ret


; --------------------------------
; Determines whether an object with ID (L7468_focus_object_id) is present
; in either the current area, or a given area.
; Input:
; - a: area ID to check (0 for current area)
; Output:
; - a: 0 if object found, 1 if object not found
; - ix: ptr to the object
Lb286_find_object_by_id:
    push hl
    push de
    push bc
        or a
        jr nz, Lb2b1_find_area_a
        ; We want to check objects in the current area:
        ld ix, (L7463_global_area_objects)
        ld a, (L7465_global_area_n_objects)
        or a
        jr z, Lb2a8
        ld b, a
        ld d, 0
        ld a, (L7468_focus_object_id)
Lb29c_object_in_current_area_loop:
        cp (ix + OBJECT_ID)
        jr z, Lb2ee_object_found
        ld e, (ix + OBJECT_SIZE)
        add ix, de
        djnz Lb29c_object_in_current_area_loop
Lb2a8:
        ld ix, (L6ad1_current_area_objects)
        ld a, (L6ad0_current_area_n_objects)
        jr Lb2d5
Lb2b1_find_area_a:
        ld l, a
        ld a, (Ld082_n_areas)
        ld b, a
        ld a, l
        ld hl, Ld0d1_area_offsets
Lb2ba_find_area_loop:
        ; Get area ptr:
        ld e, (hl)
        inc hl
        ld d, (hl)
        inc hl
        ld ix, Ld082_n_areas
        add ix, de
        cp (ix + AREA_ID)
        jr z, Lb2cd_area_found
        djnz Lb2ba_find_area_loop
        jr Lb2ea_object_not_found
Lb2cd_area_found:
        ld a, (ix + AREA_N_OBJECTS)
        ld de, AREA_HEADER_SIZE
        add ix, de
Lb2d5:
        or a
        jr z, Lb2ea_object_not_found
        ld b, a
        ld d, 0
        ld a, (L7468_focus_object_id)
Lb2de:
        cp (ix + OBJECT_ID)
        jr z, Lb2ee_object_found
        ld e, (ix + OBJECT_SIZE)
        add ix, de
        djnz Lb2de
Lb2ea_object_not_found:
        ld a, 1
        jr Lb2ef_done
Lb2ee_object_found:
        xor a
Lb2ef_done:
    pop bc
    pop de
    pop hl
    ret


; --------------------------------
; Pointers to the different animation frames of the "throw rock" animation:
Lb2f3_rock_animation_frames:
    dw L7f1e_stone_viewport_sprite_size2 + 1
    dw L7fee_stone_viewport_sprite_size3 + 1
    dw L909c_stone_viewport_sprite_size4 + 1


; --------------------------------
; Processes the following input key functions:
; - INPUT_SWITCH_BETWEEN_MOVEMENT_AND_POINTER
; - INPUT_MOVEMENT_POINTER_ON_OFF
; - INPUT_MOVE_POINTER_LEFT
; - INPUT_MOVE_POINTER_RIGHT
; - INPUT_MOVE_POINTER_UP
; - INPUT_MOVE_POINTER_DOWN
; - INPUT_THROW_ROCK
; - INPUT_ACTION
Lb2f9_execute_pressed_key_function:
    cp INPUT_SWITCH_BETWEEN_MOVEMENT_AND_POINTER
    jr nz, Lb340_no_movement_pointer_toggle
    ; Toogle movement <-> pointer:
    ld a, 9
    ld (L74a5_interrupt_timer), a
    ; Toogle the movement/pointer mode flag:
    ld a, (L6b1c_movement_or_pointer)
    cpl
    ld (L6b1c_movement_or_pointer), a
    or a
    ld a, (L6b20_display_movement_pointer_flag)
    ld hl, L7d88_action_pointer_viewport_sprite
    jr nz, Lb325_switch_to_pointer
    ; Switched to movement:
    call Lcd14_restore_view_port_background_after_drawing_sprite
    or a
    call nz, Lb537_redraw_with_center_pointer
    ld a, 96
    ld (L6b1a_pointer_x), a
    ld a, 56
    ld (L6b1b_pointer_y), a
    jr Lb355_play_sfx_and_return
Lb325_switch_to_pointer:
    ; Switched to pointer:
    or a
    call nz, Lb537_redraw_with_center_pointer
    ld a, 96
    ld (L6b1a_pointer_x), a
    sub 4
    ld (hl), a  ; pointer sprite x
    ld a, 56
    ld (L6b1b_pointer_y), a
    inc hl
    sub 4
    ld (hl), a  ; pointer sprite y
    dec hl
    call Lcc19_draw_viewport_sprite_with_offset
    jr Lb355_play_sfx_and_return

Lb340_no_movement_pointer_toggle:
    cp INPUT_MOVEMENT_POINTER_ON_OFF
    jr nz, Lb363_no_movement_pointer_on_off
    ; Movement pointer toggle:
    ; If we are in pointer mode, ignore:
    ld a, (L6b1c_movement_or_pointer)
    or a
    jp nz, Lb536_execute_pressed_key_function_done
    ld a, (L6b20_display_movement_pointer_flag)
    cpl
    ld (L6b20_display_movement_pointer_flag), a
    call Lb537_redraw_with_center_pointer
Lb355_play_sfx_and_return:
    ld a, SFX_MENU_SELECT
    call Lc4ca_play_SFX
Lb35a_pause_loop:
    ld a, (L74a5_interrupt_timer)
    or a
    jr nz, Lb35a_pause_loop
    jp Lb536_execute_pressed_key_function_done

Lb363_no_movement_pointer_on_off:
    ld b, a
    ld a, (L6b1c_movement_or_pointer)
    or a
    ld a, b
    jp z, Lb464_movement_mode_functions
    ; Pointer mode:
    ld hl, L7d88_action_pointer_viewport_sprite
    cp INPUT_MOVE_POINTER_LEFT
    jr nz, Lb386_no_pointer_move_left
    ; Move pointer left:
    call Lcd14_restore_view_port_background_after_drawing_sprite
    ld a, (L6b1a_pointer_x)
    sub 2
    or a  ; OPTIMIZATION: unnecessary, as "sub 2" already does this test
    jr z, Lb382_hit_left_border
    cp -1
    jr nz, Lb398_assign_pointer_x_position
Lb382_hit_left_border:
    ld a, 1
    jr Lb398_assign_pointer_x_position
Lb386_no_pointer_move_left:
    cp INPUT_MOVE_POINTER_RIGHT
    jr nz, Lb386_no_pointer_horizontal_movement
    ; Move pointer right:
    call Lcd14_restore_view_port_background_after_drawing_sprite
    ld a, (L6b1a_pointer_x)
    add a, 2
    cp 192
    jr c, Lb398_assign_pointer_x_position
    ; Reached the right border:
    ld a, 192
Lb398_assign_pointer_x_position:
    ld (L6b1a_pointer_x), a
    sub 4
    ld (hl), a  ; hl = L7d88_action_pointer_viewport_sprite
    jr Lb3d1_pointer_movement_pause
Lb386_no_pointer_horizontal_movement:
    cp INPUT_MOVE_POINTER_UP
    jr nz, Lb3b4_no_pointer_movement_no_pointer_move_up
    call Lcd14_restore_view_port_background_after_drawing_sprite
    ld a, (L6b1b_pointer_y)
    add a, 2
    cp 111
    jr c, Lb3c9
    ld a, 111
    jr Lb3c9
Lb3b4_no_pointer_movement_no_pointer_move_up:
    cp INPUT_MOVE_POINTER_DOWN
    jr nz, Lb3df_no_pointer_movement
    call Lcd14_restore_view_port_background_after_drawing_sprite
    ld a, (L6b1b_pointer_y)
    sub 2
    cp 255
    jr z, Lb3c8
    cp 254
    jr nz, Lb3c9
Lb3c8:
    xor a
Lb3c9:
    ld (L6b1b_pointer_y), a
    inc hl  ; hl was L7d88_action_pointer_viewport_sprite
    sub 4
    ld (hl), a
    dec hl
Lb3d1_pointer_movement_pause:
    call Lcc19_draw_viewport_sprite_with_offset
    ld hl, 1000  ; Wait for a 1000 iterations of the loop below
Lb3d7_pause_loop:
    dec hl
    ld a, h
    or l
    jr nz, Lb3d7_pause_loop
    jp Lb536_execute_pressed_key_function_done

Lb3df_no_pointer_movement:
    cp INPUT_THROW_ROCK
    jp nz, Lb464_movement_mode_functions
    ; Throw a rock at the current pointer position:
    ld a, SFX_THROW_ROCK_OR_LAND
    call Lc4ca_play_SFX
    ; Start the rock at the bottom-center of the screen.
    ld d, SCREEN_WIDTH * 8 / 2
    ld e, 0  ; 
    ld hl, L7ee0_stone_viewport_sprite_size1 + 1
    ld (hl), e  ; y
    dec hl
    ld (hl), d  ; x
    call Lcc19_draw_viewport_sprite_with_offset
    ld a, (L6b1a_pointer_x)
    ld b, a
    sub d
    ld d, a  ; d = (L6b1a_pointer_x) - rock x
    ld a, (L6b1b_pointer_y)
    ld c, a
    sub e
    ld e, a  ; e = (L6b1a_pointer_y) - rock y
    ld ix, Lb2f3_rock_animation_frames
    ld hl, L7ee0_stone_viewport_sprite_size1
    ld a, 3
Lb40b_throw_rock_animation_loop:
    push af
        ld a, 2
        ld (L74a5_interrupt_timer), a
Lb411_wait_loop:  ; OPTIMIZATION: this "wait for interrupt" occurs so many times in the code, that a small function would save a lot of bytes.
        ld a, (L74a5_interrupt_timer)
        or a
        jr nz, Lb411_wait_loop
        ; Remove the stone gfx 
        call Lcd14_restore_view_port_background_after_drawing_sprite
        sra d  ; x: Amount we want to move the rock to (1/2 the remaining distance to the player pointer)
        sra e  ; y
        ld h, (ix + 1)  ; get the pointer to the next rock sprite (it gets smaller at each frame)
        ld l, (ix)
        inc ix
        inc ix
        ld a, c
        sub e
        ld (hl), a  ; Set new "y" coordinate
    pop af
    push af
        dec a
        sub (hl)
        neg
        ld (hl), a  ; Correct the "y" coordinate since each animation frame is smaller than the previous
        dec hl
        ld a, b
        sub d
        ld (hl), a  ; Set the new "x" coordinate
    pop af
    push af
        dec a
        sub (hl)
        neg
        ld (hl), a  ; Correct the "x" coordinate since each animation frame is smaller than the previous
        call Lcc19_draw_viewport_sprite_with_offset
    pop af
    dec a
    jr nz, Lb40b_throw_rock_animation_loop
    call Lcd14_restore_view_port_background_after_drawing_sprite
    call Lb607_find_object_under_pointer
    ld a, 4  ; value to set to L747f_player_event
    ld hl, L6adf_game_boolean_variables + 3
    bit 5, (hl)
    jr z, Lb461
    ld l, a  ; l = 4
    ld a, (L6acf_current_area_id)
    cp 21  ; "THE TUBE" area
    jr z, Lb460
    cp 16  ; "LIFT SHAFT" area
    jr z, Lb460
    inc l  ; l = 5 (value to set to L747f_player_event)
Lb460:
    ld a, l
Lb461:
    jp Lb533_done_setting_L747f_player_event_to_a

Lb464_movement_mode_functions:
    ; Movement mode:
    cp INPUT_ACTION
    jp nz, Lb536_execute_pressed_key_function_done
    call Lb607_find_object_under_pointer
    ld a, (L7480_under_pointer_object_ID)
    or a
    jp z, Lb536_execute_pressed_key_function_done
    ; Player requested to interact with an object:
    ld (L7468_focus_object_id), a
    xor a  ; area ID = check current area
    call Lb286_find_object_by_id  ; look for the object in (L7468_focus_object_id)
    or a
    jp nz, Lb536_execute_pressed_key_function_done
    ; object found (pointer in "ix")
    ld iy, L6aad_player_current_x
    ld b, a
    ld c, a  ; bc = 0 (accumulates manhattan distance to object center)
    ld d, 3
    ; 3 iterations, one for "x", onr for "y", one for "z":
Lb486_coordinate_loop:
    ld a, (L6abc_current_room_scale)
    ld h, a
    add a, a
    add a, a
    add a, h  ; a = room scale * 5
    ld l, (ix + OBJECT_SIZE_X)
    cp l
    jp c, Lb536_execute_pressed_key_function_done
    ; Only interact with objects of size room scale * 5 or less
    ; Note: why?! Maybe a shortcut since all large objects are not interact-able?
    ; room scale * 8 >= object size x
    push de
        ld h, 0
        ld d, h
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        ex de, hl  ; de = object size * 32 (half width of object)
        ld l, (ix + OBJECT_X)
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, de  ; hl = object position * 64 + object size * 32  (object center)
        ld e, (iy)
        ld d, (iy + 1)  ; de = player position
        or a
        sbc hl, de  ; hl = (object position * 64 + object size * 32) - player position
        jp p, Lb4bb
        ; if negative, get absolute value of distance:
        ld a, h
        cpl
        ld h, a
        ld a, l
        cpl
        ld l, a
        inc hl
Lb4bb:
        add hl, bc
        ld b, h
        ld c, l  ; add the distance to the object in the accumulator "bc"
        inc ix
        inc iy
        inc iy
    pop de
    dec d
    jr nz, Lb486_coordinate_loop
    ld h, b
    ld l, c
    ld a, (L6abc_current_room_scale)
    cp 2
    jr c, Lb4d7
    ld e, a
    xor a
    ld d, a
    ; (a, hl) = distance
    ; de = room scale
    call La1cc_a_hl_divided_by_de_signed  ; (a, hl) = distance normalized by room scale
Lb4d7:
    ld de, 300
    xor a
    sbc hl, de  ; hl = normalized distance - 300
    ld hl, L6d29_text_out_of_reach
    jp p, Lb518_display_message
    ld b, a
    ld de, -3
    add ix, de  ; undo the offsetting the loop above had done to ix
    ld a, (ix + OBJECT_TYPE_AND_FLAGS)
    and #0f
    ld c, a  ; c = object type
    ld hl, L6b2c_expected_object_size_by_type
    add hl, bc
    ld c, (hl)
    ld a, (ix + OBJECT_SIZE)
    sub c
    jr z, Lb515_no_effect
    dec a

    ; This loop iterates over the rules stored in the object, and if any
    ; is ready to fire, it terminates, setting a 2 in L747f_player_event.
Lb4fb_rule_loop:
    add ix, bc  ; ix = pointer to the rule data.
    ld d, a  ; left over size - 1
    ld a, (ix)  ; rule type and flags
    ld c, a
    and #c0  ; keep flags
    cp #c0  ; if it is ready to fire
    jr z, Lb531_done_setting_L747f_player_event_to_2
    ; Ignore rule, move to the next
    ld a, c
    and #3f
    ld c, a
    ld hl, L6b3c_rule_size_by_type
    add hl, bc
    ld c, (hl)
    ld a, d
    sub c
    jr nc, Lb4fb_rule_loop

    ; We exhausted all the rules, no effect:
Lb515_no_effect:
    ld hl, L6d39_text_no_effect
Lb518_display_message:
    ld a, 42
    ld (L74a5_interrupt_timer), a
    ld ix, L735a_ui_message_row_pointers
    ld de, #0f00
    call Ld01c_draw_string
    ld a, (L746c_game_flags + 1)
    or #20
    ld (L746c_game_flags + 1), a
    jr Lb536_execute_pressed_key_function_done
Lb531_done_setting_L747f_player_event_to_2:
    ld a, 2
Lb533_done_setting_L747f_player_event_to_a:
    ld (L747f_player_event), a
Lb536_execute_pressed_key_function_done:
    ret


; --------------------------------
; Draws the center movement pointer in the screen, and then redraws the whole viewport.
; It adds a small delay, to allow for the SFX of toggling movement to pointer.
Lb537_redraw_with_center_pointer:
    push hl
        ld a, 9
        ld (L74a5_interrupt_timer), a
        call Lcd8c_draw_movement_center_pointer
        call L9d46_render_3d_view
        call La298_render_buffer_render
    pop hl
    ret


; --------------------------------
; If we are in pointer mode, draw the pointer, otherwise, do nothing.
Lb548_draw_pointer_if_pointer_mode:
    push hl
    push af
        ld a, (L6b1c_movement_or_pointer)
        or a
        jr z, Lb564_movement
        ld hl, L7d88_action_pointer_viewport_sprite
        ld a, (L6b1a_pointer_x)
        sub 6
        ld (hl), a
        inc hl
        ld a, (L6b1b_pointer_y)
        sub 6
        ld (hl), a
        dec hl
        call Lcc19_draw_viewport_sprite_with_offset
Lb564_movement:
    pop af
    pop hl
    ret


; --------------------------------
; Determines the order in which the pixels are drawn during the fade-in effect.
Lb567_fade_in_current_pixel_ordering:
    dw Lb569_fade_in_pixel_orderingss
Lb569_fade_in_pixel_orderingss:
    db 0, 2, 1, 3
    db 1, 3, 0, 2
    db 3, 1, 2, 0
    db 2, 0, 3, 1


; --------------------------------
; Draws the render buffer to the video memory with a fade-in effect.
Lb579_render_buffer_fade_in:
    push ix
    push iy
    push hl
    push de
    push bc
    push af
        ld a, 4  ; The fade-in has 4 steps (at each step 1/4th of the pixels are drawn).
Lb583_fade_in_loop:
        push af
            dec a
            sla a
            sla a
            ld c, a
            ld b, 0  ; bc = (a - 1) * 4
            ld hl, Lb569_fade_in_pixel_orderingss
            add hl, bc
            ld (Lb567_fade_in_current_pixel_ordering), hl
            ld ix, L725c_videomem_row_pointers
            ld a, SCREEN_HEIGHT * 8
            push af
                ld hl, L5cbc_render_buffer
                ld iy, (Lb567_fade_in_current_pixel_ordering)
                and 3
                jr z, Lb5a9
                ; a = 4 - a
                sub 4
                neg
Lb5a9:
                ld c, a
                add iy, bc
Lb5ac_row_loop:
                push hl
                    ld e, (ix)
                    ld d, (ix + 1)  ; de = video memory pointer where to draw this row
                    ; We will copy pixels from "hl" (render buffer) to "de" (video memory)
                    inc ix
                    inc ix  ; next pointer
                    ld c, (iy)
                    ld b, 0
                    add hl, bc
                    ex de, hl
                        add hl, bc
                    ex de, hl
                    ld b, SCREEN_WIDTH / 4
                    ld a, 0
                    cp (iy)
                    jr z, Lb5cd_column_loop
                    jp m, Lb5cd_column_loop
                    inc b  ; In this corner case, we need to draw 7 bytes, instead of 6
Lb5cd_column_loop:
                    ; copy one out of each 4 bytes:
                    ld a, (hl)
                    ld (de), a
                    inc hl
                    inc hl
                    inc hl
                    inc hl
                    inc de
                    inc de
                    inc de
                    inc de
                    djnz Lb5cd_column_loop
                    ld bc, SCREEN_WIDTH
                pop hl
                add hl, bc
            pop af
            dec a
            jr z, Lb5ef_fade_in_step_done
            push af
                inc iy
                and 3
                jr nz, Lb5ac_row_loop
                ; Every four loops, reset iy to Lb569_fade_in_pixel_orderingss
                ld iy, (Lb567_fade_in_current_pixel_ordering)
                jr Lb5ac_row_loop
Lb5ef_fade_in_step_done:
        pop af
        dec a
        jr nz, Lb583_fade_in_loop
        ld a, (L747a_requested_SFX)
        or a
        call nz, Lc4ca_play_SFX
        xor a
        ld (L747a_requested_SFX), a
    pop af
    pop bc
    pop de
    pop hl
    pop iy
    pop ix
    ret


; --------------------------------
; Finds the object that is direcly under the player pointer,
; and stores its ID in (L7480_under_pointer_object_ID).
; Output:
; - (L7480_under_pointer_object_ID): ID of the object clicked. Since this is reset each game loop,
;   the method assumes it is 0 at start.
Lb607_find_object_under_pointer:
    push ix
    push iy
    push hl
    push de
    push bc
    push af
        ld iy, L6754_current_room_object_projected_data
        ld a, (L746b_n_objects_to_draw)
        or a
        jp z, Lb7ca_return
        ; Since objects are drawn first to last, when checking what is under the 
        ; player pointer, we should check starting from the last object (the one drawn
        ; on top). Hence, we get the pointer to the last object first:
        ld b, a  ; number of objects in screen
        ld l, a
        dec l
        ld h, 0
        add hl, hl
        add hl, hl
        ex de, hl
        add iy, de  ; iy = pointer to the last object projected in screen
Lb624_object_loop:
        push bc
            ld l, (iy)
            ld h, (iy + 1)  ; Pointer to the projected vertex data
            ld c, (hl)  ; object ID
            inc hl
            ld a, (hl)  ; number of faces
            or a
            jp z, Lb7c0_next_object

            bit 7, a  ; Check if the object covers the whole screen
            jp nz, Lb7b4_object_under_pointer_found
            ld b, a  ; b = number of faces
            inc hl
            push hl
            pop ix  ; ix = pointer fo face data
Lb63c_face_loop:
            push bc
                ld (L74fa_object_under_pointer__current_face), ix  ; save the pointer to the face data
                ld a, (ix)
                inc ix
                and #0f
                ld l, a  ; l = number of vertices in this face
                ld d, 0
                ld b, d
                ld a, (L6b1a_pointer_x)
                ld e, a
                ld a, (L6b1b_pointer_y)
                ld c, a
                xor a
                ; This check if the pointer (x, y) are inside of the bounding
                ; box defined by the points of the face.
Lb655_face_vertex_loop:
                push hl
                    ; At this point:
                    ; - a: accumulates the checks being done
                    ; - de: pointer x
                    ; - bc: pointer y 
                    ld l, (ix)  ; vertex screen x
                    ld h, 0
                    or a
                    sbc hl, de  ; vertex x - pointer x
                    jr z, Lb66b_x_match
                    jp p, Lb667
                    ; pointer to the left:
                    or #01
                    jr Lb66d_y_check
Lb667:
                    ; pointer to the right:
                    or #02
                    jr Lb66d_y_check
Lb66b_x_match:
                    or #04
Lb66d_y_check:
                    ld l, (ix + 1)  ; vertex screen y
                    ld h, 0
                    or a
                    sbc hl, bc  ; vertex y - pointer y
                    jr z, Lb682_y_match
                    jp p, Lb67e
                    or #08
                    jr Lb684
Lb67e:
                    or #10
                    jr Lb684
Lb682_y_match:
                    or #20
Lb684:
                    inc ix  ; next vertex:
                    inc ix
                pop hl
                dec l
                jr nz, Lb655_face_vertex_loop
                ; If the pointer was to the left of some and to the right of some points,
                ; and above of some and below some, that means it's inside the bounding box.
                bit 5, a
                jr nz, Lb69a_check_y  ; if same x coordinate than a point, match for sure
                bit 4, a
                jp z, Lb7bb_next_face
                bit 3, a
                jp z, Lb7bb_next_face
                ; Left of some and right of some:
Lb69a_check_y:
                bit 2, a
                jr nz, Lb6a8_pointer_inside_face_bounding_box  ; if same y coordiante than a point, match for sure
                bit 1, a
                jp z, Lb7bb_next_face
                bit 0, a
                jp z, Lb7bb_next_face

Lb6a8_pointer_inside_face_bounding_box:
                ; Checks have succeeded, and we are within the bounding box of the
                ; projected face!
                ; Make a copy of the vertices of the current face:
                ld hl, (L74fa_object_under_pointer__current_face)
                ld a, (hl)
                and #0f  ; a = number of vertices in this face
                inc hl
                ld de, L7482_object_under_pointer__current_face_vertices
                ld c, a
                sla c
                ld b, 0
                ldir

                ; Check if the face is just a line (2 vertexes):
                cp 2
                ld b, a
                jr nz, Lb6c1_duplicate_first_vertex
                dec b
                jr Lb6cb_vertex_copy_finished
Lb6c1_duplicate_first_vertex:
                ; We copy over the first vertex at the end of the face. So, we have "number of sedges + 1" vertices.
                ld hl, (L74fa_object_under_pointer__current_face)
                inc hl
                ld a, (hl)
                ld (de), a
                inc hl
                inc de
                ld a, (hl)
                ld (de), a
Lb6cb_vertex_copy_finished:
                ; At this point:
                ; b = number of edges in the face (b == 1 for lines).
                ; iy = pointer to the object we are chacking
                push iy
                    ld iy, L7482_object_under_pointer__current_face_vertices
                    xor a
                    ld (L74fc_object_under_pointer__projected_xs_at_pointer_y), a
Lb6d5_face_edge_loop:
                    push bc
                        ld a, (L6b1b_pointer_y)
                        ld e, a
                        ld d, 0  ; de = pointer y
                        ld l, (iy + 1)
                        ld h, d  ; hl = vertex y

                        xor a
                        sbc hl, de
                        jr z, Lb704_y_match
                        jp p, Lb6ec_vertex_higher_than_pointer
                        or 1  ; vertex 1 lower than pointer
                        jr Lb6ee
Lb6ec_vertex_higher_than_pointer:
                        or 2  ; vertex 1 higher than pointer
Lb6ee:
                        ld l, (iy + 3)
                        ld h, d  ; hl = next vertex y
                        or a
                        sbc hl, de
                        jr z, Lb704_y_match
                        jp p, Lb6fe
                        or 1  ; vertex 2 lower than pointer
                        jr Lb700
Lb6fe:
                        or 2  ; vertex 2 higher than pointer
Lb700:
                        cp 3  ; if a == 3, pointer y is in between the two vertices y coordinates.
                        jr nz, Lb77c_next_edge
Lb704_y_match:
                        ld a, (iy + 1)  ; vertex y
                        cp (iy + 3)  ; next vertex y
                        jp nz, Lb713_pointer_within_vertical_span_of_segment
                        ; horizontal segment.
                        ; BUG? This determines collision too fast, as we have only checked "y",
                        ; but "x" has not been checked. It could be a horizontal segment that
                        ; does not intersect with the player pointer!
                        ; I think the problem is that hirizontal segments imply infinite slope
                        ; in the code below, and the programmers did not want to add another
                        ; special case to handle this. So, they added this shortcut, which might
                        ; some times fail.
                    pop bc
                pop iy
                jp Lb7b3_object_under_pointer_found_pop

Lb713_pointer_within_vertical_span_of_segment:
                        ; At this point, we know that the pointer "y" is within the "y" coordinages of the
                        ; two vertices defining this segment:
                        ld a, (iy)
                        cp (iy + 2)
                        jr z, Lb768  ; if it's a vertical segment
                        ld l, (iy + 2)
                        ld h, 0  ; hl = next vertex x
                        ld e, a
                        ld d, h  ; de = vertex x
                        or a
                        sbc hl, de  
                        ex de, hl  ; de = next vertex x - vertex x
                        ld l, (iy + 3)
                        ld h, 0  ; hl = next vertex y
                        ld c, (iy + 1)
                        ld b, h  ; bc = vertex y
                        or a
                        sbc hl, bc  ; hl = next vertex y - vertex y
                        ld a, h
                        ld h, l
                        ld l, b  ; 0
                        sra a
                        rr h
                        rr l  ; (a, hl) = 128 * (next vertex y - vertex y)
                        ; compute the edge slope (times 128)
                        call La1cc_a_hl_divided_by_de_signed  ; (a, hl) = 128 * (next vertex y - vertex y) / (next vertex x - vertex x)
                        push hl
                            ld a, (iy)  ; vertex x
                            call La108_a_times_hl_signed  ; (a, hl) = vertex x * 128 * slope
                            push hl
                            push af
                                ld a, (L6b1b_pointer_y)
                                ld h, 0
                                ld l, a  ; hl = pointer y
                                ld d, h
                                ld e, (iy + 1)  ; de = vertex y
                                or a
                                sbc hl, de  ; hl = pointer y - vertex y
                                ld b, h
                                ld h, l
                                ld l, 0
                                sra b
                                rr h
                                rr l  ; (b, hl) = 128 * (pointer y - vertex y)
                                ex de, hl  ; (b, de) = 128 * (pointer y - vertex y)
                            pop af
                            pop hl
                            ; 24 bit addition:
                            add hl, de
                            adc a, b  ; (a, hl) = vertex x * 128 * slope + 128 * (pointer y - vertex y)
                        pop de
                        call La1cc_a_hl_divided_by_de_signed
                        ; OPTIMIZATION: the calculation above can be greatly simplified (see my derivation below for a simpler way to do the same calculation).
                        ld a, l  ; a = (vertex x * 128 * slope + 128 * (pointer y - vertex y)) / 128 * slope
                                 ; a = (vertex x * slope + (pointer y - vertex y)) / slope
                                 ; a = vertex x + (pointer y - vertex y) / slope
Lb768:
                        ; Write "a" (vertex x at the "y" coordinate of the pointer) to the next position in "L74fc_object_under_pointer__projected_xs_at_pointer_y"
                        ; Only up to 5 values can be stored.
                        ld c, a
                        ld a, (L74fc_object_under_pointer__projected_xs_at_pointer_y)
                        inc a
                        cp 6
                        jr z, Lb77c_next_edge
                        ld (L74fc_object_under_pointer__projected_xs_at_pointer_y), a  ; increment the counter of number of points saved.
                        ld hl, L74fc_object_under_pointer__projected_xs_at_pointer_y
                        ld d, 0
                        ld e, a
                        add hl, de
                        ld (hl), c  ; save the point
Lb77c_next_edge:
                        inc iy
                        inc iy
                    pop bc
                    dec b
                    jp nz, Lb6d5_face_edge_loop
                pop iy

                ; At this point we have a list of "x coordinates" in the array, corresponding
                ; edges intersecting the "y" coordinate of the pointer. If we see that the
                ; pointer "x" matches any, or is left of some and right of some others, then 
                ; we know we have clicked on this object's face.
                ld a, (L74fc_object_under_pointer__projected_xs_at_pointer_y)
                or a
                jr z, Lb7bb_next_face
                ld b, a
                ld hl, L74fc_object_under_pointer__projected_xs_at_pointer_y + 1
                ld a, (L6b1a_pointer_x)
                ld d, 0
                ld e, a  ; de = pointer x
                xor a
Lb798_coordinate_loop:
                ld c, (hl)
                push hl
                    ld l, c
                    ld h, 0
                    or a
                    sbc hl, de  ; edge x - pointer x
                pop hl
                jr z, Lb7b3_object_under_pointer_found_pop  ; match!
                jp p, Lb7aa
                or 1  ; pointer above
                jr Lb7ac
Lb7aa:
                or 2  ; pointer below
Lb7ac:
                inc hl
                djnz Lb798_coordinate_loop
                cp 3  ; if a == 3 here, we have clicked on this object's face!
                jr nz, Lb7bb_next_face
Lb7b3_object_under_pointer_found_pop:
            pop bc
Lb7b4_object_under_pointer_found:
            ld a, c
            ld (L7480_under_pointer_object_ID), a
        pop bc
        jr Lb7ca_return
Lb7bb_next_face:
            pop bc
            dec b
            jp nz, Lb63c_face_loop
Lb7c0_next_object:
            ; Advance to the next object (in reverse order):
            ld bc, -4
            add iy, bc
        pop bc
        dec b
        jp nz, Lb624_object_loop
Lb7ca_return:
    pop af
    pop bc
    pop de
    pop hl
    pop iy
    pop ix
    ret


; --------------------------------
; Auxiliary variables for Lb7e2_execute_script:
Lb7d3:  ; Unused?
    db #16, #00
Lb7d5:  ; Unused? (only written to, never read)
    db #5f
Lb7d6_skip_rule_flag:  ; rules (except types 44 and 45) will be skipped if this is != 0.
    db #19
    db #71
Lb7d8_current_rule_type:
    db #fd
    db #67, #1b, #62, #60, #6c, #61, #6c, #a5, #62  ; Unused?


; --------------------------------
; Executes a script.
; Input:
; - a: script size
; - ix: script pointer (skipping the size byte).
Lb7e2_execute_script:
    push ix
    push iy
    push hl
    push de
    push bc
    push af
        ld c, a  ; c = rule size (in bytes)
        xor a
        ld (L7471_event_rule_found), a
        ld (Lb7d5), a
        ld (Lb7d6_skip_rule_flag), a
Lb7f5_rule_loop:
        push bc
            ld a, (L747f_player_event)
            ld h, a  ; h = event
            ld a, (ix)  ; rule type
            ld b, a
            and #3f  ; remove flags
            ld (Lb7d8_current_rule_type), a
            ld l, a  ; l = rule type without flags
            ld a, b
            and #c0  ; a = flags of rule type
                     ; The flags determine which event will a rule match with:
                     ; - #00: movement
                     ; - #40: timer
                     ; - #80: stone throwing
                     ; - #c0: interact
            cp #40
            jr nz, Lb811
            ; Flags are #40: only consider timer events
            bit 3, h  ; check if it was a timer event.
            jr nz, Lb82a_condition_matches_event
            jr Lb823_next_rule

Lb811:
            cp #80
            jr nz, Lb81b
            ; Flags are #80: only consider stone throwing events
            bit 2, h  ; throwing stone event
            jr nz, Lb82a_condition_matches_event
            jr Lb823_next_rule

Lb81b:
            cp #c0
            jr nz, Lb826
            ; Flags are #c0:  ; only consider interact events
            bit 1, h  ; interact event
            jr nz, Lb82a_condition_matches_event
Lb823_next_rule:
            jp Lbbe8_next_rule

Lb826:
            ; Flags are #00:  ; only consider movement events
            bit 0, h  ; movement event
            jr z, Lb823_next_rule

Lb82a_condition_matches_event:
            ld a, 1
            ld (L7471_event_rule_found), a
            ld a, l  ; rule type
            cp RULE_TYPE_UNSET_SKIP_RULE
            jr nz, Lb837

            ; Note: (for a potential future cleaned version). The following code
            ;       is a very large "switch" statement for each rule type. It would
            ;       have been much cleaner to have a jump table here.

            ; Rule type 45 (#2d): continue executing next rule.
            xor a
            jr Lb840
Lb837:
            cp RULE_TYPE_FLIP_SKIP_RULE
            jr nz, Lb846

            ; Rule type 44 (#2c): flip "continue executing" flag.
            ld a, (Lb7d6_skip_rule_flag)
            xor 1
Lb840:
            ld (Lb7d6_skip_rule_flag), a
Lb843_next_rule:
            jp Lbbe8_next_rule

Lb846:
            ld b, a
            ld a, (Lb7d6_skip_rule_flag)
            or a
            jr nz, Lb843_next_rule  ; skip this rule

            ld a, b  ; rule type
            cp RULE_TYPE_ADD_TO_SCORE
            jr nz, Lb861

            ; Rule type 1 (#01): Gain points
            ld e, (ix + 1)
            ld d, (ix + 2)
            ld b, (ix + 3)
            call Lbc0c_add_de_to_score
            jp Lbbe8_next_rule

Lb861:
            cp RULE_TYPE_STRENGTH_UPDATE
            jr nz, Lb889

            ; Rule type 19 (#13): Strength update
            ld hl, L6b0a_current_strength
            di
            ld a, (hl)  ; Get the current strength
            ld d, (ix + 1)  ; Get the amount to add (possible negative)
            bit 7, d
            jr nz, Lb87a_subtract_strength
            add a, d
            ; Make sure we do not overflow:
            cp MAX_STRENGTH
            jr c, Lb884
            ld a, MAX_STRENGTH
            jr Lb884
Lb87a_subtract_strength:
            add a, d
            jp p, Lb884
            ; If strength reaches 0, game over!
            ld a, GAME_OVER_REASON_YOU_COLLAPSE
            ld (L7479_current_game_state), a
            xor a
Lb884:
            ld (hl), a  ; write the strength back
            ei
            jp Lbbe8_next_rule

Lb889:
            ; Rule types 3, 4, 5, 16, 30, 31 (#03, #04, #05, #10, #1e, #1f):
            cp RULE_TYPE_TOGGLE_OBJECT_VISIBILITY
            jr z, Lb8a2
            cp RULE_TYPE_MAKE_OBJECT_VISIBILE
            jr z, Lb8a2
            cp RULE_TYPE_MAKE_OBJECT_INVISIBILE
            jr z, Lb8a2
            cp RULE_TYPE_DESTROY_OBJECT
            jr z, Lb8a2
            cp RULE_TYPE_END_RULE_IF_OBJECT_INVISIBLE
            jr z, Lb8a2
            cp RULE_TYPE_END_RULE_IF_OBJECT_VISIBLE
            jp nz, Lb98a
Lb8a2:
            ld a, (ix + 1)  ; Get the new focus object ID
            ld (L7468_focus_object_id), a
            xor a
            push ix
                call Lb286_find_object_by_id
                or a
                jr nz, Lb8bc  ; If the object was not found, next rule skipping.
                ld a, (Lb7d8_current_rule_type)
                cp RULE_TYPE_END_RULE_IF_OBJECT_INVISIBLE
                jr nz, Lb8c4

                ; Rule 30 (#1e): end rule if object is invisible
                ; Check if the object is invisible: (bit 6 = 1 -> invisible)
                ; - if object is visible, we will go to next rule,
                ; - otherwise, we will go to next rule, but skipping.
                bit 6, (ix)
Lb8bc:
            pop ix
            jp z, Lbbe8_next_rule
            jp Lbbe3_next_rule_skipping

Lb8c4:
                cp RULE_TYPE_END_RULE_IF_OBJECT_VISIBLE
                jr nz, Lb8d4

                ; Rule 31 (#1e): end rule if object is visible
                ; Check if the object is hideen: (bit 6 = 1 -> invisible)
                ; - if object is invisible, we will go to next rule,
                ; - otherwise, we will go to next rule, but skipping.
                bit 6, (ix)
            pop ix
            jp nz, Lbbe8_next_rule
            jp Lbbe3_next_rule_skipping

Lb8d4:
                bit 5, (ix)
                jp nz, Lb985_next_rule
                ; If object is not "destroyed" (bit 5), continue:
            pop hl  ; Recover the pointer to the original object
            push hl
                bit 6, (hl)  ; check if the original object is visible
                jr nz, Lb8e6  ; jump if already visible
                ld hl, L7477_render_buffer_effect
                ld (hl), 1  ; fade in effect
Lb8e6:
                cp RULE_TYPE_DESTROY_OBJECT
                jr nz, Lb8f0

                ; Rule 16 (#10): destroy object
                set 5, (ix)  ; set object as destroyed
                jr Lb92a_make_object_invisible

Lb8f0:
                cp RULE_TYPE_TOGGLE_OBJECT_VISIBILITY
                jr nz, Lb8fc

                ; Rule 3 (#03): Toggle object visibility
                bit 6, (ix)
                jr nz, Lb900_make_object_visible  ; make object visible
                jr Lb92a_make_object_invisible  ; make object invisible

Lb8fc:
                cp RULE_TYPE_MAKE_OBJECT_VISIBILE
                jr nz, Lb92a_make_object_invisible

                ; Rule 4 (#04): make object visible
Lb900_make_object_visible:
                bit 6, (ix)
                jp z, Lb985_next_rule
                res 6, (ix)  ; make object visible
                ld a, (ix)
                and #0f
                cp OBJECT_TYPE_SPIRIT
                jr nz, Lb91a
                ; Object just appeared!
                ld hl, L7469_n_spirits_found_in_current_area
                inc (hl)
                jr Lb945

Lb91a:
                set 4, (ix)
                ld a, 1
                ld (L7474_check_if_object_crushed_player_flag), a
                ld hl, L746c_game_flags
                set 2, (hl)
                jr Lb985_next_rule

Lb92a_make_object_invisible:
                ; Rule 5 (#05): Make object invisible
                bit 6, (ix)  ; if already invisible, next rule
                jr nz, Lb985_next_rule
                set 6, (ix)  ; make object invisible
                ld a, (ix)
                and #0f
                cp OBJECT_TYPE_SPIRIT
                jr nz, Lb94c
                ; A spirit was destroyed:
                ld hl, L7469_n_spirits_found_in_current_area
                ld a, (hl)
                or a
                jr z, Lb985_next_rule
                dec (hl)  ; decrease number of spirits
Lb945:
                ld hl, L746c_game_flags + 1
                set 4, (hl)  ; refresh spirit meter flag
                jr Lb985_next_rule

Lb94c:
                ; Object just disappeared, check if player needs to fall, and
                ; remove the object from the projected objects buffers:
                ld a, 1
                ld (L7475_call_Lcba4_check_for_player_falling_flag), a
                ld iy, L6754_current_room_object_projected_data
                ld a, (L746b_n_objects_to_draw)
                or a
                jr z, Lb985_next_rule
                ld b, a
                ld de, 4
                ld a, (L7468_focus_object_id)
Lb962_object_rule:
                ld l, (iy)
                ld h, (iy + 1)
                ld c, (hl)
                cp c  ; is it the disappeared object?
                jr z, Lb972_focus_object_is_on_camera
                add iy, de  ; next object
                djnz Lb962_object_rule
                ; The disappeared object is not on camera
                jr Lb985_next_rule

Lb972_focus_object_is_on_camera:
                inc hl
                bit 7, (hl)  ; Check if the disappeared object covered the whole screen
                jr z, Lb97e
                ld a, (L7481_n_objects_covering_the_whole_screen)
                dec a
                ld (L7481_n_objects_covering_the_whole_screen), a
Lb97e:
                ld (hl), 0  ; remove it from the projected objects list.
                ld hl, L746c_game_flags + 1
                set 3, (hl)  ; re-render flag
Lb985_next_rule:
            pop ix
            jp Lbbe8_next_rule

Lb98a:
            ; Rule types 6, 7, 8, 17, 32, 33 (#06, #07, #08, #11, #20, #21):
            ; same as above, but have an extra argument to specify the object area.
            cp RULE_TYPE_TOGGLE_OBJECT_FROM_AREA_VISIBILITY
            jr z, Lb9a2
            cp RULE_TYPE_MAKE_OBJECT_FROM_AREA_VISIBILE
            jr z, Lb9a2
            cp RULE_TYPE_MAKE_OBJECT_FROM_AREA_INVISIBILE
            jr z, Lb9a2
            cp RULE_TYPE_DESTROY_OBJECT_FROM_AREA
            jr z, Lb9a2
            cp RULE_TYPE_END_RULE_IF_OBJECT_FROM_AREA_INVISIBLE
            jr z, Lb9a2
            cp RULE_TYPE_END_RULE_IF_OBJECT_FROM_AREA_VISIBLE
            jr nz, Lba05
Lb9a2:
            ld a, (ix + 2)  ; object ID
            ld (L7468_focus_object_id), a
            ld a, (ix + 1)  ; area ID
            push ix
                call Lb286_find_object_by_id
                or a
                jr nz, Lba00_next_rule_pop
                ld a, (Lb7d8_current_rule_type)
                cp RULE_TYPE_END_RULE_IF_OBJECT_FROM_AREA_INVISIBLE
                jr nz, Lb9c6

                ; Rule type 32 (#20): end rule if object is invisible (from another area)
                ; Check if the object is invisible: (bit 6 = 1 -> invisible)
                ; - if object is visible, we will go to next rule,
                ; - otherwise, we will go to next rule, but skipping.
                bit 6, (ix)
            pop ix
            jp z, Lbbe8_next_rule
            jp Lbbe3_next_rule_skipping

Lb9c6:
                cp RULE_TYPE_END_RULE_IF_OBJECT_FROM_AREA_VISIBLE
                jr nz, Lb9d6

                ; Rule type 33 (#21): end rule if object is visible (from another area)
                ; Check if the object is hideen: (bit 6 = 1 -> invisible)
                ; - if object is invisible, we will go to next rule,
                ; - otherwise, we will go to next rule, but skipping.
                bit 6, (ix)
            pop ix
            jp nz, Lbbe8_next_rule
            jp Lbbe3_next_rule_skipping

Lb9d6:
                bit 5, (ix)
                jr nz, Lba00_next_rule_pop
                ; If object is not "destroyed" (bit 5), continue:
                cp RULE_TYPE_DESTROY_OBJECT_FROM_AREA
                jr nz, Lb9e6

                ; Rule type 17 (#11): destroy object (from another area)
                set 5, (ix)
                jr Lb9fc_make_object_invisible

Lb9e6:
                cp RULE_TYPE_TOGGLE_OBJECT_FROM_AREA_VISIBILITY
                jr nz, Lb9f2

                ; Rule type 6 (#06): Toggle object visibility (from another area)
                bit 6, (ix)
                jr nz, Lb9f6_make_object_visible  ; make object visible
                jr Lb9fc_make_object_invisible  ; make object invisible

Lb9f2:
                cp RULE_TYPE_MAKE_OBJECT_FROM_AREA_VISIBILE
                jr nz, Lb9fc_make_object_invisible
Lb9f6_make_object_visible:

                ; Rule type 7 (#07): make object visible (from another area) 
                res 6, (ix)
                jr Lba00_next_rule_pop

Lb9fc_make_object_invisible:

                ; Rule type 8 (#08): make object invisible (from another area) 
                set 6, (ix)
Lba00_next_rule_pop:
            pop ix
            jp Lbbe8_next_rule

Lba05:
            ; Rule types 9, 10, 11, 20, 46, 47 (#09, #0a, #0b, #14, #2d, #2f):
            ; Deal with game variables.
            cp RULE_TYPE_INCREMENT_VARIABLE
            jr z, Lba1d
            cp RULE_TYPE_DECREMENT_VARIABLE
            jr z, Lba1d
            cp RULE_TYPE_END_RULE_IF_VARIABLE_DIFFERENT
            jr z, Lba1d
            cp RULE_TYPE_SET_VARIABLE
            jr z, Lba1d
            cp RULE_TYPE_END_RULE_IF_VARIABLE_LARGER
            jr z, Lba1d
            cp RULE_TYPE_END_RULE_IF_VARIABLE_LOWER
            jr nz, Lba5d
Lba1d:
            ld e, (ix + 1)  ; Variable index
            dec e
            ld d, 0
            ld hl, L6aee_game_variables
            add hl, de  ; Get pointer to variable

            cp RULE_TYPE_INCREMENT_VARIABLE
            jr nz, Lba2e

            ; Rule type 9 (#09): increment variable
            inc (hl)
            jr Lba5a_next_rule

Lba2e:
            cp RULE_TYPE_DECREMENT_VARIABLE
            jr nz, Lba35

            ; Rule type 10 (#0a): decrement variable
            dec (hl)
            jr Lba5a_next_rule

Lba35:
            ld e, (ix + 2)  ; get value
            cp RULE_TYPE_SET_VARIABLE
            jr nz, Lba3f

            ; Rule type 20 (#14): set variable to value
            ld (hl), e
            jr Lba5a_next_rule

Lba3f:
            cp RULE_TYPE_END_RULE_IF_VARIABLE_DIFFERENT
            jr nz, Lba49

            ; Rule type 11 (#0b): if variable != value, skip rest of script.
            ld a, e
            cp (hl)
            jr nz, Lba57_next_rule_skipping
            jr Lba5a_next_rule

Lba49:
            cp RULE_TYPE_END_RULE_IF_VARIABLE_LARGER
            jr nz, Lba53

            ; Rule type 46 (#2e): if variable > value, skip rest of script.
            ld a, e
            cp (hl)
            jr c, Lba5a_next_rule
            jr Lba57_next_rule_skipping

Lba53:
            ; Rule type 47 (#2f): if variable < value, skip rest of script.
            ld a, (hl)
            cp e
            jr c, Lba5a_next_rule
Lba57_next_rule_skipping:
            jp Lbbe3_next_rule_skipping

Lba5a_next_rule:
            jp Lbbe8_next_rule

Lba5d:
            ; Rule types 12, 13, 14, 29 (#0c, #0d, #0e, #1d):
            ; Operations on boolean variables (used for storing collected keys in this game):
            cp RULE_TYPE_SET_BOOLEAN_TRUE
            jr z, Lba6d
            cp RULE_TYPE_SET_BOOLEAN_FALSE
            jr z, Lba6d
            cp RULE_TYPE_END_RULE_IF_BOOLEAN_DIFFERENT
            jr z, Lba6d
            cp RULE_TYPE_TOGGLE_BOOLEAN
            jr nz, Lbab6
Lba6d:
            ld e, a  ; save the rule type for later
            ld hl, L6adf_game_boolean_variables
            ld a, (ix + 1)  ; bit we want to modify
            dec a
            ; Get to the correct byte of the boolean variables:
Lba75_byte_loop:
            cp 8
            jr c, Lba7e_byte_found
            sub 8  ; next byte
            inc hl
            jr Lba75_byte_loop

Lba7e_byte_found:
            ld d, 1  ; mask
            or a
            jr z, Lba88
            ; Generate a one-hot bit mask for the target bit (in "d"):
            ld b, a
Lba84_bit_mask_loop:
            sla d
            djnz Lba84_bit_mask_loop
Lba88:
            ld a, e  ; restore the rule type
            ld e, (hl)
            cp RULE_TYPE_TOGGLE_BOOLEAN
            jr nz, Lba94

            ; Rule type 29 (#1d): toggle bit
            ld a, d
            and e
            jr z, Lba98_set_bit
            jr Lbaa1_reset_bit

Lba94:
            cp RULE_TYPE_SET_BOOLEAN_TRUE
            jr nz, Lba9d

Lba98_set_bit:
            ; Rule type 12 (#0c): set bit
            ld a, d
            or e
            ld (hl), a
            jr Lbab3

Lba9d:
            cp RULE_TYPE_SET_BOOLEAN_FALSE
            jr nz, Lbaa7

Lbaa1_reset_bit:
            ; Rule type 13 (#0d): reset bit
            ld a, d
            cpl
            and e
            ld (hl), a
            jr Lbab3

Lbaa7:
            ; Rule type 14 (#0e): end script if bit is different than expected value
            ld a, d
            and e
            jr z, Lbaad
            ld a, 1
Lbaad:
            cp (ix + 2)  ; exected value
            jp nz, Lbbe3_next_rule_skipping
Lbab3:
            jp Lbbe8_next_rule

Lbab6:
            cp RULE_TYPE_PLAY_SFX
            jr z, Lbad2_play_sfx
            cp RULE_TYPE_REQUEST_SFX_NEXT_FRAME
            jr nz, Lbadb

            ; Rule type 28 (#1c): request SFX to be played in next frame.
            ld hl, (L746c_game_flags)
            ; If a re-render or re-projection is requested, schedule
            ; the SFX to play afterwards. Otherwise, play now (as there will be no timing difference):
            bit 2, l
            jr nz, Lbac9_request_sfx
            bit 3, h
            jr z, Lbad2_play_sfx
Lbac9_request_sfx:
            ld a, (ix + 1)
            ld (L747a_requested_SFX), a
            jp Lbbe8_next_rule

Lbad2_play_sfx:
            ; Rule type 15 (#0f): play SFX.
            ld a, (ix + 1)  ; SFX ID
            call Lc4ca_play_SFX
            jp Lbbe8_next_rule

Lbadb:
            cp RULE_TYPE_TELEPORT
            jr nz, Lbb36

            ; Rule type 18 (#12): Teleport to a new area
            ld a, (L6acf_current_area_id)
            ld (L7470_previous_area_id), a
            ld a, SFX_GAME_START
            ld (L747a_requested_SFX), a
            ld a, (ix + 1)  ; Get target area
            ld (L6acf_current_area_id), a
            ld h, a
            ld a, (ix + 2)  ; Get object that determines position to go to
            ld (L7467_player_starting_position_object_id), a
            call La563_load_and_reset_new_area
            ld a, h  ; requested area ID to go to
            ld hl, L6ae3_visited_areas

            ; Get to the byte containing the bit representing the target area.
Lbafe_byte_loop:
            cp 8
            jr c, Lbb07
            inc hl
            sub 8
            jr Lbafe_byte_loop

Lbb07:
            ; Get a one-hot bit mask for the bit representing this area.
            ld c, 1
            ld b, a
            or a
            jr z, Lbb11
Lbb0d_bit_mask_loop:

            sla c
            djnz Lbb0d_bit_mask_loop
Lbb11:

            ld a, (hl)
            and c
            jr nz, Lbb1e_area_already_visited
            ; New area visited, mark it as visited, and
            ; add 25000 points!
            ld a, (hl)
            or c
            ld (hl), a
            ld de, 25000
            call Lbc0c_add_de_to_score
Lbb1e_area_already_visited:
            ld hl, #fffc  ; redraw everything
            ld a, (L6adf_game_boolean_variables + 3)
            ; Check if game complete flag is set, to play the
            ; escaped SFX:
            bit 6, a
            jr z, Lbb30
            ld a, SFX_OPEN_ESCAPED
            ld (L747a_requested_SFX), a
            ld hl, #0004  ; reproject
Lbb30:
            ld (L746c_game_flags), hl
            jp Lbbe8_next_rule

Lbb36:
            cp RULE_TYPE_SHOW_MESSAGE
            jp nz, Lbb87

            ; Rule type 34 (#22): Display text message
            push ix
                ld a, (ix + 1)  ; text message to display
                ld b, a
                ld hl, L6cc9_text_overpowered  ; The first text message (ignoring " PRESS ANY KEY ")
                dec b
                jr z, Lbb4d
                ld de, 16  ; size of text messages.
Lbb4a_text_message_ptr_loop:
                add hl, de
                djnz Lbb4a_text_message_ptr_loop
Lbb4d:
                ld ix, L735a_ui_message_row_pointers
                ld de, #0f00
                call Ld01c_draw_string
                ld a, (L7479_current_game_state)
                or a
                jr nz, Lbb69
                ld a, 50  ; wait 50 interrupts before refreshing the text.
                ld (L74a5_interrupt_timer), a
                ld a, 32  ; request refreshing the room name.
                ld hl, L746c_game_flags + 1
                or (hl)
                ld (hl), a
Lbb69:
            pop ix
            jp Lbbe8_next_rule

    ; Unreachable code?
    push bc
    ld e, (ix)
    ld d, (ix + 1)
    inc ix
    inc ix
    ldi
    ld b, 22
    ld a, (hl)
    inc hl
Lbb7f:
    ld (de), a
    inc de
    djnz Lbb7f
    ldi
    pop bc
    ret

Lbb87:
            cp RULE_TYPE_RENDER_EFFECT
            jr nz, Lbb94

            ; Rule type 35 (#23): trigger rendere effect (fade-in, gate open/closing, etc.)
            ld a, (ix + 1)
            ld (L7477_render_buffer_effect), a
            jp Lbbe8_next_rule

Lbb94:
            cp RULE_TYPE_REDRAW
            jr nz, Lbba3

            ; Rule type 26 (#1a): triggers a whole redraw.
            call L83aa_redraw_whole_screen
            ld hl, 0
            ld (L746c_game_flags), hl
            jr Lbbe8_next_rule

Lbba3:
            cp RULE_TYPE_PAUSE
            jr nz, Lbbb5

            ; Rule type 27 (#1b): creates a small pause
            ld a, (ix + 1)  ; number of interrupts to pause for
            ld (L74a5_interrupt_timer), a
Lbbad_pause_loop:
            ld a, (L74a5_interrupt_timer)
            or a
            jr nz, Lbbad_pause_loop
            jr Lbbe8_next_rule

Lbbb5:
            cp RULE_TYPE_SELECT_OBJECT
            jr nz, Lbc03_return
        pop bc

        ; Rule type 48 (#30): select object
        ; Changes the focus object to a new one, and executes rules from that object instead.
        ld a, (ix + 1)  ; object ID
        ld (L7468_focus_object_id), a
        xor a
        call Lb286_find_object_by_id
        or a
        jr nz, Lbc03_return
        ; Object found:
        ld d, a  ; d = 0
        ld a, (ix)
        and #0f
        ld iy, L6b2c_expected_object_size_by_type
        ld e, a
        add iy, de
        ld e, (iy)
        ld a, (ix + OBJECT_SIZE)
        sub e
        jr z, Lbc03_return
        ld c, a  ; c = number of bytes left of rules
        add ix, de  ; ix = pointer to the rule data in the new object
        jp Lb7f5_rule_loop

Lbbe3_next_rule_skipping:
            ; Turns on skipping (the rest of rules will be skipped, unless a special rule reverting this is found):
            ld a, 1
            ld (Lb7d6_skip_rule_flag), a
Lbbe8_next_rule:
            ld a, (Lb7d8_current_rule_type)  ; get rule type without flags
            ld hl, L6b3c_rule_size_by_type
            ld e, a
            ld d, 0
            add hl, de
            ld e, (hl)
            add ix, de  ; skip to the next rule
            ld a, e
        pop bc
        or a  ; If the rule size is 0, return (end of sequence marker)
        jr z, Lbc03_return
        sub c
        neg
        ld c, a  ; updates the number of bytes left
        jr z, Lbc03_return
        jp p, Lb7f5_rule_loop
Lbc03_return:
    pop af
    pop bc
    pop de
    pop hl
    pop iy
    pop ix
    ret


; --------------------------------
; Adds points to the current score
; Input:
; - (b, de): points
Lbc0c_add_de_to_score:
    ld hl, (L6aeb_score)
    ld a, (L6aeb_score + 2)
    add hl, de
    adc a, b
    ld (L6aeb_score), hl
    ld (L6aeb_score + 2), a
    ret


; --------------------------------
; Converts a 32bit number (de, hl) into a decimal string.
; Input:
; - de, hl: number to convert to decimal
; - a: number of digits
Lbc1b_integer_to_ascii:
    push ix
    push hl
    push de
    push bc
    push af
        ld c, a
        ld b, 0
        add ix, bc
        ld b, a
Lbc27:
        push bc
            dec ix
            ld bc, 10
            call Lb1b7_de_hl_divided_by_bc_signed
            ld a, c
            cp 5
            jp m, Lbc40
            ld bc, 0
            or a
            sbc hl, bc
            dec hl
            jr nz, Lbc40
            dec de
Lbc40:
            add a, 48
            ld (ix), a
        pop bc
    djnz Lbc27
    pop af
    pop bc
    pop de
    pop hl
    pop ix
    ret


; --------------------------------
; Temporary variables for "Lbc52_update_UI":
Lbc4f_current_eye_compass_frame:
    db #00
Lbc50_current_rendered_spirit_meter:
    db #00
Lbc51_current_rendered_strength:
    db #00


; --------------------------------
; Updates the UI elements (keys, eye compass, strength, spirit counter).
Lbc52_update_UI:
    ; Part 1: Update keys UI:
    ld a, (L746c_game_flags + 1)
    bit 7, a
    jr z, Lbc89_no_key_redraw
    ld hl, L76cc_ui_key_bg_sprite  ; calculate sufficient pixel row pointers for the height of this sprite
    call Lca4f_calculate_pixel_row_pointers
    ld ix, L6664_row_pointers
    ld de, 0
    call Lc895_draw_sprite_to_ix_ptrs

    ld a, (L6b0c_num_collected_keys)
    or a
    jr z, Lbc7e_no_keys
    ld b, a
    ld hl, L7725_ui_key_sprite
    ld de, 34  ; x_offset of the first key.
Lbc76_draw_ui_keys_loop:
    call Lc895_draw_sprite_to_ix_ptrs
    dec e
    dec e
    dec e
    djnz Lbc76_draw_ui_keys_loop

Lbc7e_no_keys:
    ld hl, L76cc_ui_key_bg_sprite
    ld iy, L7398_key_count_ui_row_pointers
    xor a
    call Lca70_draw_sprite_from_ix_to_iy

Lbc89_no_key_redraw:
    ; Check if a new key was just taken, and update the inventory:
    ld a, (L6b0d_new_key_taken)
    or a
    jr z, Lbcd6_no_new_key  ; if (L6b0d_new_key_taken) == 0 (no new key), skip
    ld e, a
    dec e
    xor a
    ld (L6b0d_new_key_taken), a
    ld a, e  ; a = (L6b0d_new_key_taken) - 1
    cp 10
    jr nc, Lbcd6_no_new_key  ; if (L6b0d_new_key_taken) - 1 >= 0, skip
    ld hl, L6adf_game_boolean_variables
    cp 8
    jr c, Lbca4  ; if (L6b0d_new_key_taken) - 1 >= 8, hl = L6adf_game_boolean_variables + 1
    sub 8
    inc hl
Lbca4:
    ; Calculate (in "c') the one-hot mask corresponding to (L6b0d_new_key_taken) - 1
    ld c, 1
    ld b, a
    or a
    jr z, Lbcae
Lbcaa_bit_mask_loop:
    sla c
    djnz Lbcaa_bit_mask_loop
Lbcae:
    ld a, (hl)  ; Check if the corresponding bit was already set
    and c
    jr nz, Lbcd6_no_new_key  ; If already set, skip
    ld a, c
    or (hl)
    ld (hl), a  ; Set the bit corresponding to (L6b0d_new_key_taken) - 1
    ; Increment the # of collected keys:
    ld a, (L6b0c_num_collected_keys)
    ld c, a
    inc a
    ld (L6b0c_num_collected_keys), a
    ld hl, L6b0f_collected_keys
    add hl, bc
    ld (hl), e  ; Add the new key to the inventory.
    ; Update the UI with the new key:
    ; OPTIMIZATION: if "adding a key" to the inventory were done at the beginning of the function,
    ; there would be no need for the code below, as can be made to be drawn with the code above.
    ld hl, L7725_ui_key_sprite
    ld ix, L7398_key_count_ui_row_pointers
    ld d, 0
    ld a, c
    add a, a
    add a, c
    neg
    add a, 34
    ld e, a
    call Lc895_draw_sprite_to_ix_ptrs

Lbcd6_no_new_key:
    ; Part 2: Update compass eye UI:
    ld a, (L6b2b_desired_eye_compass_frame)
    ld d, a
    ld a, (Lbc4f_current_eye_compass_frame)
    cp d
    jr nz, Lbce7
    ld a, (L746c_game_flags)
    and #60
    jr z, Lbd16_eye_compass_done
Lbce7:
    ld ix, L7350_compass_eye_ui_row_pointers
    ld hl, L7792_ui_compass_eye_sprites
    ld e, 0
    ld a, d
    cp 8
    jr nz, Lbd0f
    ld d, 7
Lbcf7:
    ; Special case for eye frame 8, which requires an animation from 8 to 5:
    dec d
    call Lc895_draw_sprite_to_ix_ptrs
    ld a, 2
    ld (L74a5_interrupt_timer), a
    ; animation delay:
Lbd00_pause_loop:
    ld a, (L74a5_interrupt_timer)
    or a
    jr nz, Lbd00_pause_loop
    ld a, 5
    cp d
    jr nz, Lbcf7
    ; Back to frame 0:
    xor a
    ld (L6b2b_desired_eye_compass_frame), a
Lbd0f:
    ld (Lbc4f_current_eye_compass_frame), a
    ld d, a
    call Lc895_draw_sprite_to_ix_ptrs

Lbd16_eye_compass_done:
    ; Part 3: Update strength UI:
    ld a, (L6b0a_current_strength)
    ld d, a
    ld a, (Lbc51_current_rendered_strength)
    cp d
    jp z, Lbdf8_strength_done
    ld a, d
    ld (Lbc51_current_rendered_strength), a
    cp 3
    jr nc, Lbd59_strength_3_or_higher
    ; Strength < 3:
    ld a, (L6b0b_selected_movement_mode)
    or a
    jr z, Lbd7e_done_handling_strength
    ; If we are not crawling, but strength is < 3, switch to crawling:
    ; This makes the player crouch for crawling:
    ld hl, L6ab8_player_crawling
    dec (hl)
    ld a, (L6ab9_player_height)
    ld hl, L6abc_current_room_scale
    sub (hl)
    ld (L6ab9_player_height), a
    ld b, (hl)
    ld d, (hl)
    ld e, 0
    srl d
    rr e
    srl d
    rr e
    ld hl, (L6aaf_player_current_y)
    xor a
    sbc hl, de
    ld (L6aaf_player_current_y), hl
    ; This changes the player movement speed to crawling:
    ld a, (Ld0c8_speed_when_crawling)
    ld l, a
    xor a
    jr Lbd6e_change_movement_mode
Lbd59_strength_3_or_higher:
    cp 5
    jr nc, Lbd7e_done_handling_strength
    ; Strength 3 or 4
    ld a, (L6b0b_selected_movement_mode)
    cp 2
    jr nz, Lbd7e_done_handling_strength
    ; If we are running, but at low strength, switch to walking:
    ld a, (L6abc_current_room_scale)
    ld b, a
    ld a, (Ld0c9_speed_when_walking)
    ld l, a
    ld a, 1
Lbd6e_change_movement_mode:
    ld (L6b0b_selected_movement_mode), a
    ld a, l
    ld (L6ab5_current_speed), a
    ld h, 0
    ld a, b
    call La108_a_times_hl_signed  ; hl = hl * a
    ld (L6ab3_current_speed_in_this_room), hl
Lbd7e_done_handling_strength:
    ld hl, L7805_ui_strength_bg_sprite
    call Lca4f_calculate_pixel_row_pointers
    ld ix, L6664_row_pointers
    ld de, 0
    call Lc895_draw_sprite_to_ix_ptrs  ; Draw strength background
    ld e, 6*2  ; Move 6 pixels down
    add ix, de
    ld a, (L6b0a_current_strength)
    cp 4
    jr nc, Lbda2_bar_y_coordinate_set
    ; If strength <= 4:
    ;   move 4 - (L6b0a_current_strength) pixels down, since the smaller weights are smaller in diameter
    sub 4
    neg
    ld e, a
    add ix, de
    add ix, de
Lbda2_bar_y_coordinate_set:
    ld hl, L7891_ui_strength_bar_sprite
    ld e, d  ; e = 0
    call Lc895_draw_sprite_to_ix_ptrs  ; draw "bar" (the bar that holds the weights)

    ld hl, L78b1_ui_strength_weight_sprite
    ld de, -6 * 2
    add ix, de  ; move back up 6 pixels to draw the weights
    ld de, 5  ; x_offset = 5, frame = 0
    ld c, 61  ; Distance in pixels between the furthest appart discs.
    ld a, (L6b0a_current_strength)
    ld b, a
    or a
    jr nz, Lbdc2_non_zero_strength
    ld a, GAME_OVER_REASON_YOU_COLLAPSE
    ld (L7479_current_game_state), a
Lbdc2_non_zero_strength:
    ld a, b
    srl b
    srl b
    inc b  ; (b = (L6b0a_current_strength) / 4 + 1)
    and 3
    jr z, Lbde7_no_smaller_disc
    ; Calculate the sprite to be used for the very first disc:
    sub 4
    neg
    add a, d
    ld d, a  ; Sprite to use for the very first disc (which might be smaller)
    ; Loop that draws each of the individual weight discs in the strength visualization:
Lbdd2_individual_weight_loop:
    call Lc895_draw_sprite_to_ix_ptrs  ; Draw left disc.
    ld a, c
    sub 3  ; Each disc is 3 pixels wide
    ld c, a
    add a, e  ; Move x_offset to the right disc
    ld e, a
    call Lc895_draw_sprite_to_ix_ptrs  ; Draw right disc.
    ld a, c
    sub 3  ; Each disc is 3 pixels wide
    ld c, a
    ld a, e  ; Move x_offset to the left disc again
    sub c
    ld e, a
    ld d, 0  ; Each subsequent disc is a large one
Lbde7_no_smaller_disc:
    djnz Lbdd2_individual_weight_loop
    ld ix, L6664_row_pointers
    ld iy, L737a_strength_ui_row_pointers
    ld hl, L7805_ui_strength_bg_sprite  ; Only used to determine the width * height to copy.
    xor a
    call Lca70_draw_sprite_from_ix_to_iy  ; Copy the recently drawn strength visual to video memory.

Lbdf8_strength_done:
    ; Part 4: Update spirit meter UI:
    ld a, (L6b1f_current_spirit_meter)
    ld d, a
    ld a, (Lbc50_current_rendered_spirit_meter)
    cp d
    jr nz, Lbe09_redraw_spirit_meter
    ; If the desired and rendered values are the same, only redraw if
    ; The re-render flag is set:
    ld a, (L746c_game_flags + 1)
    and #10
    jr z, Lbe55
Lbe09_redraw_spirit_meter:
    ; The position of the spirit meter is computed based on some non trivial formula, specifically:
    ; - There is a concept of "sprit time", T, ('L6b1f_current_spirit_meter'), that starts at 32, and
    ;   increments by one each 120 seconds.
    ; - There is also a number of spirits that must be killed, N, ('Ld0cb_n_sprits_that_must_be_killed')
    ; - And the # of spirits actually killed, n, (starts at 0).
    ; - The position of the spirit meter is = T * (N - n) / N
    ; - If this position reaches 'SPIRIT_METER_MAX' (64), the game is over.
    ld a, d
    ld (Lbc50_current_rendered_spirit_meter), a
    ld hl, L7738_ui_spirit_meter_bg_sprite
    call Lca4f_calculate_pixel_row_pointers
    ld ix, L6664_row_pointers
    ld de, 8  ; x_offset = 8, frame to draw = 0
    call Lc895_draw_sprite_to_ix_ptrs
    ld a, (Ld0cb_n_sprits_that_must_be_killed)
    ld e, a
    or a
    jr z, Lbe43_draw_spirit_indicator
    ld hl, L6b09_number_of_spirits_destroyed
    sub (hl)
    ld l, a  ; l = (Ld0cb_n_sprits_that_must_be_killed) - (L6b09_number_of_spirits_destroyed)
    ld a, (Lbc50_current_rendered_spirit_meter)
    ld h, a
    call La253_h_times_l_signed  ; hl = (Lbc50_current_rendered_spirit_meter) * ((Ld0cb_n_sprits_that_must_be_killed) - (L6b09_number_of_spirits_destroyed))
    xor a
    ld d, a
    call La1cc_a_hl_divided_by_de_signed  ; (a, hl) = (a, hl) / de
    ld a, l
    cp SPIRIT_METER_MAX
    jr c, Lbe3f
    ; spirit meter reached its maximum, game over!
    ld a, GAME_OVER_REASON_OVERPOWERED
    ld (L7479_current_game_state), a
Lbe3f:
    inc l
    ld d, 0  ; frame 0 (there is only one frame here)
    ld e, l  ; x_offset (# of spirits left)
Lbe43_draw_spirit_indicator:
    ; Draw the sprite indicator with offset "e":
    ld hl, L777d_ui_spirit_meter_indicator_sprite
    call Lc895_draw_sprite_to_ix_ptrs
    ld hl, L7738_ui_spirit_meter_bg_sprite  ; Only used to get the width * height
    ld iy, L736a_spirit_count_ui_row_pointers
    ld a, 1  ; Skip the left-most byte when drawing (as that is occluded in the UI).
    call Lca70_draw_sprite_from_ix_to_iy
Lbe55:
    ret


; --------------------------------
Lbe56_interrupt_noise_status:
    db #00  ; When there is a spirit in the room, the game produces a constant noise.
Lbe57_spirit_effect_attribute_cycle:
    ; #42: 01 000 010 : red
    ; #42: 01 000 011 : magenta
    ; #42: 01 000 110 ; yellow
    db #42, #42, #43, #43, #46
Lbe5c_random_eyes_1_timer:
    db #9d, #00
Lbe5e_random_eyes_2_timer:
    db #87, #00
Lbe60_waving_flag_timer:
    db #07
Lbe61_spirit_effect_timer:
    db #0a
Lbe62_waving_flag_frame:
    db #02
Lbe63_hud_random_eyes_status:
    db #03
Lbe64_time_unit1:  ; changes once per second, and counts from 5 to 1
    db #01
Lbe65_time_unit3:  ; changes once per second, and counts from 120 to 1
    db #01


; --------------------------------
; Interrupt routine, does the following tasks:
; - Updates the background color of the viewport in case a fade-out was triggered.
; - Updates the HUD animations (eyes, waving flag).
; - Updates all the timers.
Lbe66_interrupt_routine:
    di
    push hl
    push bc
    push af
        ld hl, L747c_within_interrupt_flag
        set 7, (hl)  ; Mark we are within the interrupt
        ld hl, L74a5_interrupt_timer
        ; Drecrease (L74a5_interrupt_timer) if it's not 0:
        xor a
        cp (hl)
        jr z, Lbe77_already_zero
        dec (hl)
Lbe77_already_zero:
        ; Checks whether we need to change attributes due to a fade out:
        inc a  ; a = 1
        ld (L7478_interrupt_executed_flag), a  ; Some functions set this to 0, and wait for the interrupt to execute by waiting for this to be 1
        ld hl, Lbe61_spirit_effect_timer
        ld a, (L7479_current_game_state)
        or a
        jr nz, Lbe8a
        ; We are in a menu, or ga,e over, do not apply the spirit effect
        ld a, (L6b2a_spirit_in_room)
        or a
        jr nz, Lbe91_spirit_in_room_effect
Lbe8a:
        ld a, (hl)  ; hl = Lbe61_spirit_effect_timer
        cp 10
        jr z, Lbeb9_no_attribute_change
        jr Lbe94_fade_out_finished
Lbe91_spirit_in_room_effect:
        dec (hl)
        jr nz, Lbe9b
Lbe94_fade_out_finished:
        ld (hl), 10
        ld a, (L6ad9_current_attribute_color)
        jr Lbea5_attribute_decided
Lbe9b:
        ld c, (hl)
        srl c  ; Offset in the fade out table is (Lbe61_spirit_effect_timer)/2
        ld b, 0
        ld hl, Lbe57_spirit_effect_attribute_cycle
        add hl, bc
        ld a, (hl)  ; Get the desired attribute byte
Lbea5_attribute_decided:
        ; Change the attributes of the whole viewport to "a":
        ld hl, L5800_VIDEOMEM_ATTRIBUTES + 4 * 32 + 4
        push de
            ld de, 8  ; skip 4 rows to the right/left of the viewport
            ld c, SCREEN_HEIGHT
Lbeae_attribute_change_row_loop:
            ld b, SCREEN_WIDTH
Lbeb0_attribute_change_column_loop:
            ld (hl), a
            inc hl
            djnz Lbeb0_attribute_change_column_loop
            add hl, de
            dec c
            jr nz, Lbeae_attribute_change_row_loop
        pop de

Lbeb9_no_attribute_change:
        ; Randomly display eyes in one of the windows in the HUD:
        ld hl, (Lbe5c_random_eyes_1_timer)
        dec hl
        ld a, h
        or l
        jr nz, Lbee9_no_eyes1
        ; Update eyes:
        ld a, (Lbe63_hud_random_eyes_status)
        bit 0, a
        jr nz, Lbedc_add_eyes
        or 1
        ld (Lbe63_hud_random_eyes_status), a
        ld hl, L4000_VIDEOMEM_PATTERNS + #0ca2  ; (2, 108)
        ld (hl), #0e  ; remove eyes
        ; Randomize the amount of time until the next time we draw the eyes:
        ld a, r
        ld l, a
        ld h, 0
        add hl, hl
        inc h
        inc h
        jr Lbee9_no_eyes1
Lbedc_add_eyes:
        and 254
        ld (Lbe63_hud_random_eyes_status), a
        ld hl, L4000_VIDEOMEM_PATTERNS + #0ca2  ; (2, 108)
        ld (hl), #ae  ; draw eyes
        ld hl, 15  ; keep the eyes on for 15 interrupts
Lbee9_no_eyes1:
        ld (Lbe5c_random_eyes_1_timer), hl

        ld hl, (Lbe5e_random_eyes_2_timer)
        dec hl
        ld a, h
        or l
        jr nz, Lbf1c_no_eyes2
        ; Update eyes:
        ld a, (Lbe63_hud_random_eyes_status)
        bit 1, a
        jr nz, Lbf0f_add_eyes
        or 2
        ld (Lbe63_hud_random_eyes_status), a
        ld hl, L4000_VIDEOMEM_PATTERNS + #07bd  ; (29, 47)
        ld (hl), #e0  ; remove eyes
        ; Randomize the amount of time until the next time we draw the eyes:
        ld a, r
        ld l, a
        ld h, 0
        add hl, hl
        inc h
        inc h
        jr Lbf1c_no_eyes2
Lbf0f_add_eyes:
        and #fd
        ld (Lbe63_hud_random_eyes_status), a
        ld hl, L4000_VIDEOMEM_PATTERNS + #07bd  ; (29, 47)
        ld (hl), #ea  ; draw eyes
        ld hl, 15  ; keep the eyes on for 15 interrupts
Lbf1c_no_eyes2:
        ld (Lbe5e_random_eyes_2_timer), hl

        ; Update the waving flag in the HUD:
        ld hl, Lbe60_waving_flag_timer
        dec (hl)
        jr nz, Lbf43_no_flag_update
        ld (hl), 8
        ld a, (Lbe62_waving_flag_frame)
        inc a
        and 3
        ld (Lbe62_waving_flag_frame), a
        push de
        push ix
            ld ix, L73b4_waving_flag_row_pointers
            ld hl, L7a12_waving_flag_gfx_properties
            ld d, a
            ld e, 0
            call Lc895_draw_sprite_to_ix_ptrs  ; draws one frame of the waving flag
        pop ix
        pop de
Lbf43_no_flag_update:

        ld a, (L7479_current_game_state)
        or a
        jr nz, Lbf9f_time_update_done
        ld a, (L6b2a_spirit_in_room)
        or a
        jr z, Lbf61_no_interrupt_sound
        ; There is a spirit in the room and we need to produce sound:
        ld a, (L6ad7_current_border_color)
        ld h, a
        ld a, (Lbe56_interrupt_noise_status)
        xor 16
        ld (Lbe56_interrupt_noise_status), a
        or h
        or 8
        out (ULA_PORT), a
        xor a
Lbf61_no_interrupt_sound:

        ; Update the internal game time:
        ld hl, L6b1d_time_interrupts
        dec (hl)
        jp nz, Lbf9f_time_update_done
        ld (hl), 50
        ld hl, L6b0e_lightning_time_seconds_countdown
        cp (hl)  ; Compare with 0, as a == 0 at this point.
        jr z, Lbf71_zero_seconds
        dec (hl)
Lbf71_zero_seconds:
        ld hl, Lbe64_time_unit1
        dec (hl)
        jr nz, Lbf87_no_strength_decrease
        ld (hl), 5
        ld hl, L6b2a_spirit_in_room
        ; If there is a spirit in the room, decrease strength by 1 each 5 seconds:
        xor a
        cp (hl)
        jr z, Lbf87_no_strength_decrease
        ld hl, L6b0a_current_strength
        cp (hl)
        jr z, Lbf93_current_strength_zero
        dec (hl)  ; decrease strength
Lbf87_no_strength_decrease:
        ld hl, Lbe65_time_unit3
        dec (hl)
        jr nz, Lbf93_time_unit3_zero
        ld (hl), 120
        ld hl, L6b1f_current_spirit_meter
        inc (hl)
Lbf93_current_strength_zero:
Lbf93_time_unit3_zero:
        ld hl, L6b1e_time_unit5
        dec (hl)
        jr nz, Lbf9f_time_update_done
        ld (hl), 10
        ld hl, L6b22_time_unit6
        inc (hl)
Lbf9f_time_update_done:
        ld hl, L747c_within_interrupt_flag
        res 7, (hl)  ; Mark the interrupt has finished.
    pop af
    pop bc
    pop hl
    ei
    reti


; --------------------------------
; When reading the keyboard, if the keys read are the same as
; in the previous cycle, and this counter is == 0, we will try
; to read the keyboard again.
Ld0cf_keyboard_first_key_repeat:
    db 0
Lbfab_previous_number_of_pressed_keys:
    db 0
Lbfac_keyboard_layout:
    db 127, "ZXCV"
    db "ASDFG"
    db "QWERT"
    db "12345"
    db "09876"
    db "POIUY"
    db 13, "LKJH"
    db " ", 27, "MNB"


; --------------------------------
; Reads input from keyboard and joysticks.
; In addition to the register/flags outputs below, it also fills a set of RAM
; buffers with all the keys currently being held pressed, and how many of them
; are there currently pressed.
; Output:
;  - carry flag: any key pressed
;  - a: pressed key
Lbfd4_read_keyboard_and_joystick_input:
    push ix
    push hl
    push de
    push bc
Lbfd9_read_keyboard_and_joystick_input_internal:
        ld hl, L74f2_keyboard_input
        ld bc, #fe00 + ULA_PORT  ; start reading the top keyboard half-row
Lbfdf_keyboard_read_loop:
        in a, (c)  ; Read the status of one keyboard half-row
        cpl
        and 31
        ld (hl), a  ; Store it in L74f2_keyboard_input
        inc hl
        rlc b  ; Next half-row
        jr c, Lbfdf_keyboard_read_loop

        xor a
        ld (L749f_number_of_pressed_keys), a
        ld (L7472_symbol_shift_pressed), a
        ld de, L74a0_pressed_keys_buffer
        ld hl, L74f2_keyboard_input
        ld b, 8  ; Number of keyboard half-rows
Lbff9_keyboard_row_loop:
        ld a, (hl)
Lbffa_keyboard_row_loop_internal:
        or a
        jr z, Lc043_next_row  ; If nothing pressed in that row
        push de
            push bc
                ld b, 8
                ld c, a
                xor a
                ld e, 254
                ; Here we know for sure a key was pressed, we loop
                ; through the bits to find the one of the pressed key.
Lc005_find_pressed_key_loop:
                srl c
                jr c, Lc00e_key_pressed  ; key pressed found
                inc a
                sla e
                djnz Lc005_find_pressed_key_loop
Lc00e_key_pressed:
            pop bc
            ld c, a  ; Index of the pressed key
            ld a, 8
            sub b  ; 8 - half-row index
            ld d, a
            add a, a
            add a, a
            add a, d
            add a, c  ; a = half-row * 5 + key index
            ld c, e
            ld e, a
            ld d, 0
            ld ix, Lbfac_keyboard_layout
            add ix, de  ; ix = key corresponding to this position
            ld a, (ix)
        pop de
        cp 27  ; symbol shift key code
        jr nz, Lc031_its_not_symbol_shift
        push af
            ld a, 1
            ld (L7472_symbol_shift_pressed), a
        pop af
Lc031_its_not_symbol_shift:
        ld (de), a  ; store the key pressed 
        ld a, (L749f_number_of_pressed_keys)
        inc a
        ld (L749f_number_of_pressed_keys), a
        cp MAX_PRESSED_KEYS
        jr z, Lc094_done_reading_keys
        ; continue reading keys in this half-row, ignoring the ones
        ; we have already checked:
        inc de
        ld a, (hl)
        and c
        ld (hl), a
        jr Lbffa_keyboard_row_loop_internal
Lc043_next_row:
        inc hl
        djnz Lbff9_keyboard_row_loop

        ld a, (L7683_control_mode)
        cp CONTROL_MODE_KEMPSTON_JOYSTICK
        jr nz, Lc089_control_mode_not_kempston
        ; kemptson joystick controls:
        ld bc, 31
        in a, (c)  ; read kempston joystick status
        ld b, a
        ld a, 149
        bit 4, b
        call nz, Lc078_accumulate_key_subroutine
        ld a, 145
        bit 3, b
        call nz, Lc078_accumulate_key_subroutine
        ld a, 146
        bit 2, b
        call nz, Lc078_accumulate_key_subroutine
        ld a, 147
        bit 1, b
        call nz, Lc078_accumulate_key_subroutine
        ld a, 148
        bit 0, b
        call nz, Lc078_accumulate_key_subroutine
        jr Lc089_control_mode_not_kempston

; This is an auxiliary function defined inside of the key reading function:
Lc078_accumulate_key_subroutine:
    ld (de), a
    ld a, (L749f_number_of_pressed_keys)
    inc a
    ld (L749f_number_of_pressed_keys), a
    cp MAX_PRESSED_KEYS
    jr z, Lc086
    inc de
    ret

Lc086:
        pop bc  ; remove the return address from the stack (as there was a "call Lc078" to get here)
        jr Lc094_done_reading_keys

Lc089_control_mode_not_kempston:
        ld a, (L749f_number_of_pressed_keys)
        or a
        jr nz, Lc094_done_reading_keys
        ; No keys pressed
        ld (Lbfab_previous_number_of_pressed_keys), a
        jr Lc0ea_pop_bc_de_hl_ix_and_return
Lc094_done_reading_keys:
        ld b, a
        ld a, (Lbfab_previous_number_of_pressed_keys)
        cp b
        jr nz, Lc0bf_keys_pressed_different_than_before
        ; Same number of keys pressed as before:
        ld hl, L74a0_pressed_keys_buffer
        ld de, L74ec_previous_pressed_keys_buffer
        ; Compare the current pressed keys to the previous ones:
Lc0a1_compare_keys_to_previous_loop:
        ld a, (de)
        cp (hl)
        jr nz, Lc0bf_keys_pressed_different_than_before  ; At least one key is different
        inc de
        inc hl
        djnz Lc0a1_compare_keys_to_previous_loop
        ld a, (Ld0cf_keyboard_first_key_repeat)
        or a
        jr nz, Lc0d9_not_first_keyboard_read_attempt
        inc a
        ld (Ld0cf_keyboard_first_key_repeat), a
        ; If we have the same keys pressed as before,
        ; and (Ld0cf_keyboard_first_key_repeat) == 0, we check the keyboard again.
        ld a, (Ld0cf_keyboard_hold_delays)  ; First key press delay
        ld (L74f1), a  ; Note: I believe this is unused (written, but never read)
        ld (L74a5_interrupt_timer), a
        jp Lbfd9_read_keyboard_and_joystick_input_internal
Lc0bf_keys_pressed_different_than_before:
        xor a
        ld (Ld0cf_keyboard_first_key_repeat), a
        ld b, a
        ld a, (L749f_number_of_pressed_keys)
        ld (Lbfab_previous_number_of_pressed_keys), a
        ld c, a
        ld hl, L74a0_pressed_keys_buffer
        ld de, L74ec_previous_pressed_keys_buffer
        ldir
        ld a, (L74a0_pressed_keys_buffer)  ; return the first key pressed
        scf  ; mark that there is a key being pressed
        jr Lc0ea_pop_bc_de_hl_ix_and_return
Lc0d9_not_first_keyboard_read_attempt:
        ld a, (L74a5_interrupt_timer)
        or a
        jp nz, Lbfd9_read_keyboard_and_joystick_input_internal
        ld a, (Ld0cf_keyboard_hold_delays + 1)  ; non-first repeat keyboard delay
        ld (L74a5_interrupt_timer), a
        ld a, (L74a0_pressed_keys_buffer)  ; return the first key pressed
        scf  ; mark that there is a key being pressed
Lc0ea_pop_bc_de_hl_ix_and_return:
    pop bc
    pop de
    pop hl
    pop ix
    ret


; --------------------------------
; Gets the initial area pointers, and initializes the following variables accordingly:
; - L746e_global_rules_ptr
; - L7465_global_area_n_objects
; - L7463_global_area_objects
Lc0f0_get_initial_area_pointers:
    push ix
    push hl
    push de
    push bc
    push af
        ld de, Ld082_area_reference_start
        ld hl, (Ld0c6_global_rules_offset)
        add hl, de
        ld (L746e_global_rules_ptr), hl
        ld a, (Ld0ca_speed_when_running)
        ld (L6ab5_current_speed), a
        xor a
        ld (L6abe_use_eye_player_coordinate), a
        ld (L6abd_cull_by_rendering_volume_flag), a  ; turn on volume culling
        ld a, (Ld082_n_areas)
        ld b, a
        ld a, #ff
        ld hl, Ld0d1_area_offsets
Lc116_find_area_loop:
        ld e, (hl)
        inc hl
        ld d, (hl)
        inc hl
        ld ix, Ld082_area_reference_start
        add ix, de
        cp (ix + AREA_ID)
        jr z, Lc12d_area_found
        djnz Lc116_find_area_loop
        xor a
        ld (L7465_global_area_n_objects), a
        jr Lc13c_area_not_found
Lc12d_area_found:
        ld a, (ix + AREA_N_OBJECTS)
        ld (L7465_global_area_n_objects), a
        ld de, AREA_HEADER_SIZE
        add ix, de
        ld (L7463_global_area_objects), ix
Lc13c_area_not_found:
    pop af
    pop bc
    pop de
    pop hl
    pop ix
    ret


; --------------------------------
; Searches the area with ID (L6acf_current_area_id), loads it into the 
; game variables, and resets all the necessary state.
Lc143_load_and_reset_current_area:
    push ix
    push hl
    push de
    push bc
    push af
        xor a
        ld (L6b21_time_unit6_previous), a
        ld (L6b22_time_unit6), a
        inc a
        ld (L7475_call_Lcba4_check_for_player_falling_flag), a
        ld (L7466_need_attribute_refresh_flag), a
        ld (L7477_render_buffer_effect), a  ; fade in effect
        ld a, (Ld082_n_areas)
        ld b, a
        ld a, (L6acf_current_area_id)
        ld hl, Ld0d1_area_offsets
Lc164_find_area_loop:
        ld e, (hl)
        inc hl
        ld d, (hl)
        inc hl
        ld ix, Ld082_n_areas
        add ix, de
        cp (ix + AREA_ID)
        jr z, Lc178_area_found
        djnz Lc164_find_area_loop
        jp Lc1f3_done
Lc178_area_found:
        ld a, (ix + AREA_FLAGS)
        ld (L6b19_current_area_flags), a
        ld a, (ix + AREA_N_OBJECTS)
        ld (L6ad0_current_area_n_objects), a
        ld e, (ix + AREA_RULES_OFFSET)
        ld d, (ix + AREA_RULES_OFFSET + 1)
        push ix
            add ix, de
            ld (L6ad5_current_area_rules), ix
        pop ix
        ld a, (ix + AREA_SCALE)
        ld (L6abc_current_room_scale), a
        ld b, a
        ld a, (L6ab5_current_speed)
        ld l, a
        ld h, 0
        ld a, b
        call La108_a_times_hl_signed
        ld (L6ab3_current_speed_in_this_room), hl
        ld l, b
        ld a, (Ld0cc_max_failling_height_in_room_units)
        ld h, a
        call La253_h_times_l_signed
        ld a, l
        ld (L6aba_max_falling_height_without_damage), a
        ld l, b
        ld a, (Ld0cd_max_climbable_height_in_room_units)
        ld h, a
        call La253_h_times_l_signed
        ld a, l
        ld (L6abb_max_climbable_height), a
        ld l, b
        ld a, (L6ab8_player_crawling)
        ld h, a
        call La253_h_times_l_signed
        ld a, l
        ld (L6ab9_player_height), a
        ld d, 0
        ld a, (ix + AREA_ATTRIBUTE)
        ld (L6add_desired_attribute_color), a
        ld l, (ix + AREA_NAME)
        ld h, d
        ld e, 8
        add ix, de  ; ix += 8 (skip header)
        ld (L6ad1_current_area_objects), ix
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        ld de, L6f49_area_names
        add hl, de  ; hl = #6f49 + (ix + 7) * 16
        ld de, L6abf_current_area_name_string
        ld bc, 16
        ldir
        call Lc81c_reset_global_area_objects
Lc1f3_done:
    pop af
    pop bc
    pop de
    pop hl
    pop ix
    ret


; --------------------------------
Lc1fa_text_spaces:
    db 0, "                       "
Lc212:
    db 103  ; Number of rows to compute pointers for.
Lc213_last_described_key:
    db 0  ; Last key for which description message was shown.
Lc214_key_description_message_indexes:
    ; These index the "L6cb9_game_text" array.
    db #34, #36, #3a, #3d, #41, #47, #4b, #4d, #4f, #50
Lc21e:
    dw #0f00
Lc220:  ; Note: I believe this is unused (written, but never read)
    dw #0d00
Lc222_text_dash:
    db #00, '-'


; --------------------------------
; Load/Save/Quit menu
Lc224_load_save_quit_menu:
    ; If the number of keys pressed is != 1, just return:
    ld a, (L749f_number_of_pressed_keys)
    cp 1
    jp nz, Lc39a_return

    ld a, 6
    ld (L7479_current_game_state), a

    ; Clear the render buffer:
    ld hl, L5cbc_render_buffer
    ld d, h
    ld e, l
    inc de
    ld (hl), 0
    ld bc, (SCREEN_HEIGHT * 8 + 1) * SCREEN_WIDTH - 1
    ldir

    ld hl, Lc212 - 1  ; Compute pointers for 103 rows
    call Lca4f_calculate_pixel_row_pointers
    call Lc39b_update_number_of_collected_keys_text
    call Lc3cb_update_number_of_spirits_destroyed_text
    call Lc3b8_update_score_text
    ld hl, L721a_text_asterisks
    ld ix, L6664_row_pointers + 9 * 2
    ld de, #130b  ; length 19, offset 11
    call Ld01c_draw_string
    ld ix, L6664_row_pointers + 96 * 2
    call Ld01c_draw_string
    ld hl, L7d1f_text_save_load_quit
    ld ix, L6664_row_pointers + 24 * 2
    ld de, #1406
    call Ld01c_draw_string
    ld hl, L7d34_text_keys
    ld ix, L6664_row_pointers + 45 * 2
    ld de, #040d
    call Ld01c_draw_string
    ld hl, L7d4a_text_collected
    ld de, (49694)
    call Ld01c_draw_string
    ld hl, L7d39_text_spirits
    ld ix, L6664_row_pointers + 56 * 2
    ld de, #0704
    call Ld01c_draw_string
    ld hl, L7d5a_text_destroyed
    ld de, (49696)
    call Ld01c_draw_string
    ld hl, L7d41_text_strength
    ld ix, L6664_row_pointers + 67 * 2
    ld de, #080d
    call Ld01c_draw_string
    ld de, 11  ; size of each strength text
    ld hl, L71c9_text_status_array
    ; Strength text is "(L6b0a_current_strength - 1) / 4"
    ld a, (L6b0a_current_strength)
    dec a
Lc2b3_strength_text_loop:
    sub 4
    jr c, Lc2ba
    add hl, de
    jr Lc2b3_strength_text_loop
Lc2ba:
    ld de, #0967
    call Ld01c_draw_string  ; Draw current strength
    ld hl, L7d6a_text_score
    ld ix, L6664_row_pointers + 78 * 2
    ld de, #0f23
    call Ld01c_draw_string

    xor a
    ld (Lc213_last_described_key), a
    ; Clear the row pointers:
    ld hl, L6664_row_pointers
    ld d, h
    ld e, l
    inc de
    ld (hl), a
    ld bc, 240 - 1
    ldir

    ; Set the attributes to grey:
    ld a, (L6ad9_current_attribute_color)
    ld e, a
    ld a, 7  ; attribute to set the screen area to
    ld (L6add_desired_attribute_color), a
    call Lb252_set_screen_area_attributes

    ld a, e
    ld (L6add_desired_attribute_color), a  ; Save the color attribute we had before entering in this screen.
    ld a, 1
    ld (L7466_need_attribute_refresh_flag), a  ; Set the flag on, so attributes are refreshed after exiting this screen.
    call Lb579_render_buffer_fade_in

    ; Menu main loop:
Lc2f5_wait_for_input_loop:
    call Lbfd4_read_keyboard_and_joystick_input
    jr nc, Lc2f5_wait_for_input_loop
    ld de, #0106
    cp 'S'
    jr z, Lc307
    cp 'L'
    jr nz, Lc330_no_load_or_save
    ld e, 69
Lc307:
    ; These calls draw directly to video memory, instead of to the draw buffer:
    ld hl, Lc222_text_dash
    ld ix, L725c_videomem_row_pointers + 29 * 2
    call Ld015_draw_string_without_erasing
    ld hl, Lc1fa_text_spaces
    ld de, #1404
    ld ix, L725c_videomem_row_pointers + 45 * 2
    ld bc, 22
    push af
        ; Clear 4 lines of text (drawing spaces over them):
        ld a, 4
Lc321_clear_loop:
        call Ld01c_draw_string
        add ix, bc
        dec a
        jr nz, Lc321_clear_loop
    pop af
    call L8132_load_or_save_to_tape
    jp Lc397
Lc330_no_load_or_save:
    cp 'K'  ; press 'K' to show descriptions of keys collected
    jr nz, Lc37a_K_not_pressed
    ld a, (L6b0c_num_collected_keys)
    or a
    jr z, Lc2f5_wait_for_input_loop  ; If there are no collected keys, ignore.
    ld ix, L725c_videomem_row_pointers + 45 * 2
    ld hl, Lc213_last_described_key
    ld e, (hl)
    dec a
    cp (hl)
    jr c, Lc360  ; Circle around to show the first key again.
    inc (hl)  ; Show next key:
    ld d, 0
    ld hl, L6b0f_collected_keys
    add hl, de
    ld e, (hl)
    ld hl, Lc214_key_description_message_indexes
    add hl, de
    ld b, (hl)
    ; Get the pointer to the b-th text message in L6cb9_game_text:
    ld hl, L6cb9_game_text
    ld e, 16
Lc358_get_text_ptr_loop:
    add hl, de
    djnz Lc358_get_text_ptr_loop

    ld de, #0f39
    jr Lc369
Lc360:
    ld (hl), 0
    ld hl, L7d4a_text_collected
    ld de, (Lc21e)
Lc369:
    call Ld01c_draw_string
    ld a, 25  ; wait for 25 interrupts to prevent cycling through keys too fast.
    ld (L74a5_interrupt_timer), a
Lc371_pause_loop:
    ld a, (L74a5_interrupt_timer)
    or a
    jr nz, Lc371_pause_loop
    jp Lc2f5_wait_for_input_loop
Lc37a_K_not_pressed:
    push af
        ld a, 11
        ld (L74a5_interrupt_timer), a
        call L9d46_render_3d_view
        call Lb252_set_screen_area_attributes
        call Lb579_render_buffer_fade_in
        call Lb548_draw_pointer_if_pointer_mode
    pop af

    cp 'Q'  ; press 'Q' to quite the game
    jr z, Lc39a_return
    ; Any other key, goes back to the game
Lc391_pause_loop:
    ld a, (L74a5_interrupt_timer)
    or a
    jr nz, Lc391_pause_loop
Lc397:
    ld (L7479_current_game_state), a  ; set current game state to 0 (normal play).
Lc39a_return:
    ret


; --------------------------------
; Updates the "XX COLLECTED" keys text with the actual number.
Lc39b_update_number_of_collected_keys_text:
    ld hl, L7d4a_text_collected + 2
    ld (hl), ' '
    ld d, 57
    ld a, (L6b0c_num_collected_keys)
    cp 10
    jr c, Lc3af_less_than_10
    ld d, 57
    ld (hl), '1'
    sub 10
Lc3af_less_than_10:
    add a, '0'
    inc hl
    ld (hl), a
    ld a, d
    ld (Lc21e), a  ; Update the x_offset at which to draw the key description messages
    ret


; --------------------------------
; Updates the "SCORE  XXXXXXX " string with the actual score.
Lc3b8_update_score_text:
    ld ix, L7d6a_text_score + 8  ; position of the number in the score string
    ld hl, (L6aeb_score)  ; lower 2 btes of the score
    ld a, (L6aeb_score + 2)  ; higher byte of the score
    ld e, a
    ld d, 0
    ld a, 7  ; number of digits
    call Lbc1b_integer_to_ascii
    ret


; --------------------------------
; Updates the " XX DESTROYED  " string with the actual number of spirits destroyed.
Lc3cb_update_number_of_spirits_destroyed_text:
    ld hl, L7d5a_text_destroyed + 2
    ld (hl), 32
    ld d, 67
    ld a, (L6b09_number_of_spirits_destroyed)
    ld c, '0'  ; first digit
Lc3d7:
    cp 10
    jr c, Lc3e2_tenths_found
    sub 10
    ld d, 67
    inc c  ; first digit += 1
    jr Lc3d7
Lc3e2_tenths_found:
    add a, '0'
    inc hl
    ld (hl), a  ; write tenths
    ld a, d
    ld (Lc220), a  ; update position where to draw (but this is unused).
    ld a, c
    cp '0'
    ret z
    dec hl
    ld (hl), a  ; write units
    ret


; --------------------------------
; Unused?
    db #00, #00, #0d


; --------------------------------
; Reads a filename from keyboard input.
; Output:
; - a: name length.
; - hl: pointer to the edited name.
Lc3f4_read_filename:
    push ix
    push iy
    push de
    push bc
        ld hl, (Ld0cf_keyboard_hold_delays)  ; Save previous keyboard delays
        push hl
            ld hl, #0523  ; 35 interrupts delay for first repeat, 5 interrupts delay for subsequent repeats
            ld (Ld0cf_keyboard_hold_delays), hl
            ld ix, L725c_videomem_row_pointers + 48 * 2
            ld a, '#'  ; Cursor character.
            ld (L720b_text_input_buffer + 1), a
            ; Clear the input buffer to all spaces:
            ld de, L720b_text_input_buffer + 2
            ld b, FILENAME_BUFFER_SIZE
            ld a, ' '
Lc414_clear_input_buffer_loop:
            ld (de), a
            inc de
            djnz Lc414_clear_input_buffer_loop

            ; Draws the "filename :   " and input buffer texts to screen:
            ld hl, L7d7a_text_filename
            ld b, 2
Lc41d_draw_filename_and_input_buffer_loop:
            ld de, #0d27
            call Ld01c_draw_string

            ld de, 10 * 2
            add ix, de  ; move 10 pixels down
            ld hl, L720b_text_input_buffer
            djnz Lc41d_draw_filename_and_input_buffer_loop

            ld de, -2 * 10
            add ix, de  ; move back 10 pixels up
            ld iy, L720b_text_input_buffer + 1
            ld hl, L720b_text_input_buffer
            ld de, #0d27
            ld b, 0  ; Current editing position
Lc43e_wait_for_player_input_loop:
            call Lbfd4_read_keyboard_and_joystick_input
            jr nc, Lc43e_wait_for_player_input_loop
            cp 127  ; "delete"
            jr nz, Lc466_not_delete
            ; Check if this was produced by SHIFT + '0':
            ld a, (L749f_number_of_pressed_keys)
            cp 2  ; Check if 2 keys re pressed simultaneously.
            jr nz, Lc43e_wait_for_player_input_loop
            ld a, (L74a0_pressed_keys_buffer + 1)
            cp '0'
            jr nz, Lc43e_wait_for_player_input_loop
            ld a, b
            or a  ; If we are at the beginning of the string, we cannot delete.
            jr z, Lc43e_wait_for_player_input_loop
            ; Delete last character:
            dec b
            ld (iy), ' '
            dec iy
            ld (iy), '#'
            jr Lc4a3_redraw_input_buffer
Lc466_not_delete:
            cp 27  ; symbol shift pressed
            jr nz, Lc47c_no_symbol_shift
            ; Check if it's shift + 'M' -> '.'
            ld a, (L749f_number_of_pressed_keys)
            cp 2
            jr nz, Lc43e_wait_for_player_input_loop
            ld a, (L74a0_pressed_keys_buffer + 1)
            cp 'M'
            jr nz, Lc43e_wait_for_player_input_loop
            ld a, '.'
            jr Lc493_type_character
Lc47c_no_symbol_shift:
            ld c, a
            ld a, (L749f_number_of_pressed_keys)
            cp 1
            jr nz, Lc43e_wait_for_player_input_loop
            ld a, c
            cp 13  ; enter
            jr z, Lc4a8_done_editing
            cp ' '  ; ignore anything below a space
            jp m, Lc43e_wait_for_player_input_loop
            cp 'Z' + 1  ; ignore anything above 'Z'
            jp p, Lc43e_wait_for_player_input_loop
Lc493_type_character:
            ; Make sure we do not overflow the buffer:
            ld c, a
            ld a, b
            cp FILENAME_BUFFER_SIZE
            jr z, Lc43e_wait_for_player_input_loop
            ; Add a character:
            inc b
            ld (iy), c
            inc iy
            ld (iy), '#'
Lc4a3_redraw_input_buffer:
            call Ld01c_draw_string
            jr Lc43e_wait_for_player_input_loop
Lc4a8_done_editing:
            ld (iy), ' '  ; Replace cursor by space.
            call Ld01c_draw_string
        pop hl
        ld (Ld0cf_keyboard_hold_delays), hl  ; Resore previous keyboard delays
        ld a, b
        ld hl, L720b_text_input_buffer + 1
    pop bc
    pop de
    pop iy
    pop ix
    ret


; --------------------------------
; Play SFX state
Lc4be:
    dw 0
Lc3c0:
    dw 0
Lc4c2:
    db 0
Lc4c3:
    db 0, 0
Lc4c5:
    dw 0
Lc4c7:
    db 0, 0, 0


; --------------------------------
; Plays an SFX
; Input:
; - a: SFX ID
Lc4ca_play_SFX:
    push ix
    push iy
    push hl
    push de
    push bc
    push af
        di
        dec a
        sla a
        sla a
        ld e, a
        ld d, 0  ; de = (a - 1) * 4  (offset of the SFX in the SFX table)
        ld hl, L75bf_SFX_table
        add hl, de
        ld e, (hl)
        inc hl
        ld c, (hl)
        inc hl
        ld b, (hl)
        ld (Lc4be), bc
        inc hl
        ld a, (hl)
        ld ix, Lc4c2
        ld (ix), a
        ld hl, L75fb_SFX_data
        add hl, de
        add hl, de
        add hl, de
        add hl, de
        ld a, (hl)
        inc hl
        bit 7, a
        jp nz, Lc583
        ld (ix + 4), a
        ld (Lc3c0), hl
        ld (ix + 5), 0
Lc509:
        ld b, (hl)
        ld (ix + 1), b
        inc hl
        ld a, (hl)
        ld (ix + 2), a
        inc hl
        ld a, (hl)
        ld (ix + 3), a
Lc517:
        ld a, (ix + 3)
        ld hl, 208
        call La108_a_times_hl_signed
        ld de, (Lc4be)
        call La1cc_a_hl_divided_by_de_signed
        inc hl
        push hl
            ld hl, (Lc4be)
            ld a, 7
            call La108_a_times_hl_signed
            ld de, 30
            or a
            sbc hl, de
            jp p, Lc53d
            ld hl, 1
Lc53d:
        pop de
        push ix
        push bc
            call Lc643_play_sfx_beep
        pop bc
        pop ix
        ld hl, (Lc4be)
        ld d, 0
        ld e, (ix + 2)
        bit 7, e
        jr z, Lc554
        dec d
Lc554:
        add hl, de
        ld a, h
        and 15
        ld h, a
        ld (Lc4be), hl
        djnz Lc517
        inc (ix + 5)
        ld a, (ix + 5)
        cp (ix + 4)
        jr nz, Lc578
        dec (ix)
        jp z, Lc639
        ld hl, (Lc3c0)
        ld (ix + 5), 0
        jr Lc509
Lc578:
        ld hl, (Lc3c0)
        ld d, 0
        ld e, a
        add hl, de
        add hl, de
        add hl, de
        jr Lc509
Lc583:
        ld de, Lc4c3
        ld bc, 7
        ldir
        and 127
        cp 1
        jr z, Lc5c6
        cp 2
        jr z, Lc5eb
        ld a, (Lc4c2)
        ld b, a
        ld a, 0
Lc59b:
        push bc
            ld bc, (Lc4c3)
            ld h, 0
Lc5a2:
            out (ULA_PORT), a
            xor 16
            push af
                xor a
                ld l, a
                ld d, l
                ld e, h
                sbc hl, de
                sbc hl, de
                ld e, c
                add hl, de
                ld a, l
                sub h
                jr c, Lc5b6
                dec a
Lc5b6:
                ld h, a
Lc5b7:
                dec a
                jr nz, Lc5b7
            pop af
            djnz Lc5a2
        pop bc
        djnz Lc59b
        ld a, 0
        out (ULA_PORT), a  ; black border, and no sound.
        jr Lc639
Lc5c6:
        ld b, (ix)
Lc5c9:
        push bc
            ld de, (Lc4c3)
            ld hl, (Lc4be)
Lc5d1:
            push de
                ld de, (Lc4c5)
                push hl
                    call Lc643_play_sfx_beep
                pop hl
                ld de, (Lc4c7)
                add hl, de
            pop de
            dec de
            ld a, e
            or d
            jr nz, Lc5d1
        pop bc
        djnz Lc5c9
        jr Lc639
Lc5eb:
        ld a, (ix + 4)
        ld de, #1041  ; "ld c, b; djnz ..."
        ld hl, #00fe  ; "... -3; nop"
        or a
        jr z, Lc603
        ld e, 67
        cp 2
        jr z, Lc603
        ld de, #0545  ; "ld b, l; dec b"
        ld hl, #fd20  ; "jr nz, -3"
Lc603:
        ld (Lc629_self_modifying), de
        ld (Lc62b_self_modifying), hl
        ld d, (ix)
        ld e, (ix + 1)
        ld c, (ix + 2)
        ld h, (ix + 3)
        ld l, 255
        ld a, 0
Lc61a:
        or 24
        out (ULA_PORT), a
        ld b, c
Lc61f:
        djnz Lc61f
        ld b, h
Lc622:
        djnz Lc622
        and 15
        out (ULA_PORT), a
        dec de
Lc629_self_modifying:
        nop
        nop
Lc62b_self_modifying:
        nop
        nop
        ld b, a
        ld a, (Lc4c7)
        add a, c
        ld c, a
        ld a, d
        or e
        ld l, a
        ld a, b
        jr nz, Lc61a
Lc639:
    pop af
    ei
    pop bc
    pop de
    pop hl
    pop iy
    pop ix
    ret


; --------------------------------
; Plays a "beep" (used in the play SFX function to generate the different SFX).
; Input:
; - h: duration of the beep
; - l: frequency of the beep
Lc643_play_sfx_beep:
    ld a, l
    srl l
    srl l
    cpl
    and 3
    ld c, a
    ld b, 0  ; bc = (255 - l) & #03
    ld ix, Lc658_pause
    add ix, bc  ; set the exact amount of "nops" we will execute in each loop
    ld a, 0 
    or 8  ; OPTIMIZATION: these two instructions are the same as ld a, 8
Lc658_pause:
    nop
    nop
    nop
    inc b
    inc c
Lc65d_pause_loop:
    dec c
    jr nz, Lc65d_pause_loop
    ld c, 63
    dec b
    jp nz, Lc65d_pause_loop
    xor 16  ; alternate between sound and no sound
    out (ULA_PORT), a  ; produce sound
    ld b, h
    ld c, a
    bit 4, a
    jr nz, Lc679
    ld a, d
    or e
    jr z, Lc67d
    ld a, c
    ld c, l
    dec de
    jp ix  ; jumps back to Lc658_pause (+0, +1, +2, or +3)
Lc679:
    ld c, l
    inc c
    jp ix  ; jumps back to Lc658_pause (+0, +1, +2, or +3)
Lc67d:
    ret  ; OPTIMIZATION: remove, and make the jump here just ret z


; --------------------------------
; Title screen text positions and strings:
Lc67e_title_screen_text_attributes:
    ; Each block is:
    ; - string ptr., pointer to buffer ptr.
    ; - x offset (pixel), length
    dw Lc6ae, L6664_row_pointers + 8 * 2
    db #1b, 15
Lc684:
    dw Lc6be, L6664_row_pointers + 28 * 2
    db 16, 10
Lc68a:
    dw Lc6c9, L6664_row_pointers + 38 * 2
    db 16, 19
Lc690:
    dw Lc6dd, L6664_row_pointers + 48 * 2
    db 16, 19
Lc696:
    dw Lc6f1, L6664_row_pointers + 58 * 2
    db 16, 17
Lc69c:
    dw Lc703, L6664_row_pointers + 78 * 2
    db 7, 20
Lc6a2:
    dw Lc718, L6664_row_pointers + 94 * 2
    db 25, 16
Lc6a8:
    dw Lc72b, L6664_row_pointers + 28 * 2
    db 4, 1

Lc6ae:
    db 0, "CONTROL OPTIONS"
Lc6be:
    db 0, "1 KEYBOARD"
Lc6c9:
    db 0, "2 SINCLAIR JOYSTICK"
Lc6dd:
    db 0, "3 KEMPSTON JOYSTICK"
Lc6f1:
    db 0, "4 CURSOR JOYSTICK"
Lc703:
    db 0, "ENTER: BEGIN MISSION"
Lc718:
    db 0, "% 1990 INCENTIVE"
Lc729_text_space:
    db 0, " "
Lc72b:
    db 0, "@"

    db 103  ; # of pixel rows to calculate pointers for in the title screen


; --------------------------------
; Title screen loop
Lc72e_title_screen_loop:
    push ix
    push hl
    push de
    push bc
    push af
        ; Clear the render buffer:
        ld hl, L5cbc_render_buffer
        ld d, h
        ld e, l
        inc de
        ld (hl), 0
        ld bc, (SCREEN_HEIGHT * 8 + 1) * SCREEN_WIDTH - 1
        ldir
        ld hl, Lc72b + 1
        call Lca4f_calculate_pixel_row_pointers
        ld a, 7  ; draw 7 strings
        ld hl, Lc67e_title_screen_text_attributes
Lc74c_title_screen_draw_loop:
        ld c, (hl)
        inc hl
        ld b, (hl)  ; string ptr.
        inc hl
        ld e, (hl)
        inc hl
        ld d, (hl)  ; buffer ptr.
        inc hl
        push de
        pop ix  ; ix = buffer ptr (where to draw the string).
        ld e, (hl)  ; x offset
        inc hl
        ld d, (hl)  ; string length
        inc hl
        push hl
            ld h, b
            ld l, c  ; hl = string ptr
            call Ld01c_draw_string
        pop hl
        dec a
        jr nz, Lc74c_title_screen_draw_loop

        ; Clear the pixel row pointers:
        ld hl, L6664_row_pointers
        ld d, h
        ld e, l
        inc de
        ld (hl), a
        ld bc, 10 * SCREEN_WIDTH - 1
        ldir

        ; Set the color attributes of the title screen:
        ld a, 7
        ld hl, L5800_VIDEOMEM_ATTRIBUTES + 4 * 32 + 4
        ld de, 8  ; skip 4 rows to the right/left of the viewport
        ld c, SCREEN_HEIGHT
Lc77b_title_attributes_y_loop:
        ld b, SCREEN_WIDTH
Lc77d_title_attributes_x_loop:
        ld (hl), a
        inc hl
        djnz Lc77d_title_attributes_x_loop
        add hl, de
        dec c
        jr nz, Lc77b_title_attributes_y_loop

        call Lb579_render_buffer_fade_in
        ld bc, L725c_videomem_row_pointers - L6664_row_pointers
        ld de, (Lc6a8 + 4)  ; x, y of the arrow
        jr Lc7c2_title_screen_arrow
Lc791_title_loop:
        call Lbfd4_read_keyboard_and_joystick_input
        jr nc, Lc791_title_loop
        cp 13  ; ENTER KEY
        jr z, Lc7eb_title_enter_pressed
        cp '1'
        jp m, Lc791_title_loop
        cp '5'
        jp p, Lc791_title_loop
        sub '1'
        ld l, a  ; l = 0, 1, 2, or 3 for the control mode
        ld a, (L7683_control_mode)
        cp l
        jr z, Lc791_title_loop  ; if we have not changed the mode, just loop back
        ld a, l
        ld (L7683_control_mode), a  ; set current control mode
        ld ix, (Lc6a8 + 2)  ; pointer where to draw
        add ix, bc
        ld hl, Lc729_text_space
        call Ld01c_draw_string
        ld a, SFX_MENU_SELECT
        call Lc4ca_play_SFX
Lc7c2_title_screen_arrow:
        ld a, (L7683_control_mode)
        ld hl, (Lc684 + 2)  ; keyboard string
        or a
        jr z, Lc7da
        ld hl, (Lc68a + 2)  ; sinclair joystick string
        dec a
        jr z, Lc7da
        ld hl, (Lc690 + 2)  ; kempston joystick string
        dec a
        jr z, Lc7da
        ld hl, (Lc696 + 2)  ; cursor joystick string
Lc7da:
        ld (Lc6a8 + 2), hl
        ld ix, (Lc6a8 + 2)  ; pointer where to draw
        add ix, bc  ; Go from "L6664_row_pointers" to "L725c_videomem_row_pointers".
        ld hl, Lc72b  ; arrow string
        call Ld01c_draw_string
        jr Lc791_title_loop

Lc7eb_title_enter_pressed:
        ; Adjust the input mapping, depending on the control mode:
        ld de, 9
        ld hl, L7684_input_mapping
        ld a, (L7683_control_mode)
        cp CONTROL_MODE_SINCLAIR_JOYSTICK
        jr nz, Lc805_no_sinclair_joystick
        ld (hl), '9'  ; up
        add hl, de
        ld (hl), '8'  ; down
        add hl, de
        ld (hl), '6'  ; left
        add hl, de
        ld (hl), '7'  ; right
        jr Lc810
Lc805_no_sinclair_joystick:
        ld (hl), '7'  ; up
        add hl, de
        ld (hl), '6'  ; down
        add hl, de
        ld (hl), '5'  ; left
        add hl, de
        ld (hl), '8'  ; right
Lc810:
        ld a, SFX_MENU_SELECT
        call Lc4ca_play_SFX
    pop af
    pop bc
    pop de
    pop hl
    pop ix
    ret


; --------------------------------
; Resets the state of all the objects in the current area.
Lc81c_reset_global_area_objects:
    push ix
    push hl
    push de
    push bc
    push af
        ld a, (L7465_global_area_n_objects)
        or a
        jr z, Lc874_done
        ld d, 0
        ld ix, (L7463_global_area_objects)
        ld b, a
Lc82f_object_reset_loop:
        ; Reset object flags:
        ld a, (ix + OBJECT_TYPE_AND_FLAGS)
        and #8f
        or #40
        ld (ix + OBJECT_TYPE_AND_FLAGS), a
        ld e, (ix + OBJECT_SIZE)
        add ix, de
        djnz Lc82f_object_reset_loop

        ld a, #ff
        ld (L7468_focus_object_id), a
        xor a
        call Lb286_find_object_by_id
        or a
        jr nz, Lc874_done
        ; Object with ID #ff found!
        ; This is the "global room structure of the area":
        push ix
        pop hl  ; hl = object ptr
        ld a, (ix + OBJECT_SIZE)
        sub 3
        ld b, a
        ld c, 0  ; bc = number of rooms
        ; Each byte except for 0, 7 and 8 (hence the "sub 3" above) in this object represents an object ID:
Lc857_reset_objects_in_room_structure_loop:
        inc hl
        ld a, (hl)
        or a
        jr z, Lc86a_skip_object
        ld (L7468_focus_object_id), a
        xor a
        call Lb286_find_object_by_id
        or a
        jr nz, Lc86a_skip_object
        ; Reset the state of the object pointed to in the global state:
        res 6, (ix + OBJECT_TYPE_AND_FLAGS)
Lc86a_skip_object:
        inc c
        ld a, c
        cp 6
        jr nz, Lc872
        ; skip object ID and size
        inc hl
        inc hl
Lc872:
        djnz Lc857_reset_objects_in_room_structure_loop
Lc874_done:
    pop af
    pop bc
    pop de
    pop hl
    pop ix
    ret


; --------------------------------
; Clears the render buffer, and then fades-in to this new version, effectively
; achieving a fade-out to black effect.
Lc87b_fade_out:
    push hl
    push de
    push bc
        ; Clear the render buffer:
        ld hl, L5cbc_render_buffer
        ld d, h
        ld e, l
        inc de
        ld (hl), 0
        ld bc, (SCREEN_HEIGHT * 8 + 1) * SCREEN_WIDTH - 1
        ldir
        ; Fade-in to this new black buffer:
        call Lb579_render_buffer_fade_in
    pop bc
    pop de
    pop hl
    ret


; --------------------------------
; Draw sprite local variables:
Lc892_draw_sprite_and_mask:  ; The "and-mask" to use for dropping pixels in the last byte of each row
    db #ff                   ; in case the sprite width is not a multiple of 8 pixels.
Lc893_draw_sprite_within_byte_offset:
    db #04
Lc894_mode3_tmp_storage:
    db #00


; --------------------------------
; Draws a sprite to video memory. It contains 3 alternative drawing routines:
; - mode 1 (easy): sprite is aligned to the horizontal 8-pixel grid.
; - mode 2 (shifted): sprite data needs to be shifted, as the z coordinate
;                     is not aligned to the 8-pixel grid.
; - mode 3 (over-write): in this mode, the sprite does not erase the background
;                        (only the 1s are added, but the 0s do not erase the background).
; Note: the and-mask is only applied to the last byte in each row. This is used to copy
;       graphics that have a width in pixels that is not a multiple of 8.
; Input:
; - hl: pointer to attributes: width, height, and-mask, frame size, sprite data
; - d: frame to draw (most significant bit determines drawing mode)
; - e: x_offset
; - ix: Pointer to the sequence of row pointers where to draw each row.
Lc895_draw_sprite_to_ix_ptrs:
    push ix
    push iy
    push hl
    push de
    push bc
    push af
        di  ; Disable interrupts while drawing
        ld c, (hl)  ; Width of buffer to draw in bytes
        inc hl
        ld b, (hl)  ; Height of buffer to draw in bytes
        push bc
        push de
            ld b, d
            inc hl
            ld a, (hl)  ; We read the and mask (for the last byte)
            ld (Lc892_draw_sprite_and_mask), a
            inc hl
            ld e, (hl)  ; Frame size (low byte)
            inc hl
            ld d, (hl)  ; Frame size (high byte)
            inc hl
            res 7, b
            ld a, b
            ; Get the pointer to the sprite:
            or a
            jr z, Lc8b7_ptr_set
Lc8b4_ptr_loop:
            add hl, de
            djnz Lc8b4_ptr_loop
Lc8b7_ptr_set:
        pop de
        pop bc
        ; If the "x_offset" is not a multiple of 8, use drawing mode 2
        ld a, e
        and 7
        jr nz, Lc8f5_drawing_mode2
        ; If we explicitly called for drawing mode 3, go to mode 2 first,
        ; as the check for mode 3 is there:
        bit 7, d
        jr nz, Lc8f5_drawing_mode2

        ; Drawing mode 1: Simple case, bytes can be copied directly
        ;                 (sprite aligned with the horizontal 8 pixel grid).
        ld a, e  ; Translate the pixel offset into a byte offset
        srl a
        srl a
        srl a
Lc8c9_mode1_draw_loop:
        push bc
        push af
            ; Add the drawing address "(ix)" to the pixel offset "a":
            add a, (ix)
            ld e, a
            ld a, (ix + 1)
            adc a, 0
            ld d, a

            inc ix
            inc ix  ; To get the next row pointer
            dec c  ; Copy "c - 1" bytes (hl) -> (de)
            jr z, Lc8e0_skip_copy
            ld b, 0
            ldir
Lc8e0_skip_copy:
            ; For the last byte of each row, we apply the "and mask":
            ld a, (Lc892_draw_sprite_and_mask)  ; restore the and mask
            ld c, a
            and (hl)  ; "and" with the last byte in the row
            ld b, a
            ld a, c
            cpl  ; invert "and mask" 
            ex de, hl
                and (hl)  ; "and" with the byte in the destination
                or b  ; add the masked-byte from source
                ld (hl), a  ; write result
            ex de, hl
            inc hl  ; next byte
        pop af
        pop bc
        djnz Lc8c9_mode1_draw_loop
        jp Lca3e_draw_complete

Lc8f5_drawing_mode2:
        ; Drawing mode 2:
        ; "a" contains the x_offset % 8 here:
        ld (Lc893_draw_sprite_within_byte_offset), a
        ld a, e  ; Translate the pixel offset into a byte offset
        srl a
        srl a
        srl a
        bit 7, d  ; Check if drawing mode 3 is requested:
        jp nz, Ld015_drawing_mode3
Lc904_mode2_row_loop:
        push bc
        push af
            ; Add the drawing address "(ix)" to the pixel offset "a":
            add a, (ix)
            ld e, a
            ld a, (ix + 1)
            adc a, 0
            ld d, a

            inc ix
            inc ix  ; To get the next row pointer
            push de
            pop iy  ; iy = address where to draw.
            ld d, 0
            ld e, (hl)  ; Read the byte to draw
            ld a, (Lc893_draw_sprite_within_byte_offset)
            ld b, a
            ld a, #80  ; "a" will contain the "and mask" to use
Lc920_shift_byte_loop:
            srl e
            sra a
            djnz Lc920_shift_byte_loop
            add a, a  ; we have shifted "a" one extra position to the right (since it started at #80),
                      ; so, we correct this by shifting it 1 bit to the left.
            dec c  ; Check if this sprite is just 1 byte wide
            jr nz, Lc943_mode2_wider_than_one_byte
            ; This is the last byte in this row:
            ld c, a
            ld a, (Lc893_draw_sprite_within_byte_offset)
            ld b, a
            ; we not also shift the "and mask":
            ld a, (Lc892_draw_sprite_and_mask)
            cpl
Lc933_mode2_and_mask_shift_loop:
            srl a
            djnz Lc933_mode2_and_mask_shift_loop
            or c  ; we add the "and mask" we computed above
            ; draw the byte ("iy" contains the address in video memory, and "e" the byte to draw)
            and (iy)
            or e
            ld (iy), a
            inc iy
            jr Lc987_mode2_draw_second_part_of_last_byte

Lc943_mode2_wider_than_one_byte:
            ; At this point: a = shifted "and mask" of the first part of the byte
            ;                e = shifted first part of the byte
            ;                c = width - 1
            ; Draw the first part of the byte of the first sprite:
            and (iy)
            or e
            ld (iy), a
            inc iy
            dec c  ; Check if this is the second to last byte in the row
            jr z, Lc964_mode2_second_to_last_byte
Lc94f_mode2_inner_byte_loop:
            ld d, (hl)
            inc hl
            ld e, (hl)
            ld a, (Lc893_draw_sprite_within_byte_offset)
            ld b, a
            ; Given the byte to draw, and the next one, shift both together to obtain the actual byte
            ; that we need to draw in the current video memory position:
Lc956_mode2_byte_to_draw_shift_loop:
            srl d
            rr e
            djnz Lc956_mode2_byte_to_draw_shift_loop
            ; Draw it directly, no need for an "and mask", as we are within the sprite:
            ld (iy), e
            inc iy
            dec c
            jr nz, Lc94f_mode2_inner_byte_loop

Lc964_mode2_second_to_last_byte:
            ; Draw the left-over part of the sprite:
            ld d, (hl)
            inc hl
            ld a, (Lc892_draw_sprite_and_mask)
            and (hl)
            ld e, a
            ld a, (Lc893_draw_sprite_within_byte_offset)
            ld b, a
Lc96f_mode2_and_mask_shift_loop:
            srl d
            rr e
            djnz Lc96f_mode2_and_mask_shift_loop
            ld b, a
            ld a, (Lc892_draw_sprite_and_mask)
            cpl
Lc97a_mode2_and_mask_shift_loop2:
            srl a
            djnz Lc97a_mode2_and_mask_shift_loop2
            and (iy)
            or e
            ld (iy), a
            inc iy

Lc987_mode2_draw_second_part_of_last_byte:
            ; The "second part of the byte" is the part that overlaps with the following byte, once
            ; we shift it "x_offset % 8" pixels to the right.
            ; Get the "and mask":
            ld a, (Lc892_draw_sprite_and_mask)
            ld d, a
            ld a, (Lc893_draw_sprite_within_byte_offset)
            ld b, a
            ld e, 0
            ; Shift the and mask to obtain the mask we need for the second part of the byte:
Lc991_mode2_and_mask_shift_loop2:
            srl d
            rr e
            djnz Lc991_mode2_and_mask_shift_loop2
            ld b, a
            ld a, e
            cpl
            and (iy)  ; Apply the "and mask" to the byte currently in video memory
            ld c, a
            ld d, (hl)  ; Get the byte to draw again
            inc hl
            ld e, 0
            ; Shift the byte to the right to obtain only the second part:
Lc9a2_get_second_part_of_byte_loop:
            srl d
            rr e
            djnz Lc9a2_get_second_part_of_byte_loop
            ld a, e
            or c
            ld (iy), a  ; Draw the second part of the byte.
        pop af
        pop bc
        djnz Lc9b4
        jp Lca3e_draw_complete
Lc9b4:  ; Auxiliary label, since the target of "djnz" is further than 128 bytes
        ; OPTIMIZATION: this can be done faster replacing the "djnz" by just "dec b; jp z, Lc904_mode2_row_loop"
        jp Lc904_mode2_row_loop

Ld015_drawing_mode3:
        push bc
        push af
            ; Add the drawing address "(ix)" to the pixel offset "a":
            add a, (ix)
            ld e, a
            ld a, (ix + 1)
            adc a, 0
            ld d, a

            inc ix
            inc ix  ; To get the next row pointer
            push de
            pop iy  ; iy = address where to draw.

            ld b, #ff  ; Used to insert 1s from the left when rotating the inverted version of the byte to draw
            xor a
            ld (Lc894_mode3_tmp_storage), a
Lc9d0_mode3_byte_loop:
            ld d, (hl)  ; Read the byte to draw.
            ld a, d
            cpl
            ld e, a
            ld d, b  ; d = #ff
            ld b, e  ; b, e = inverted version of the byte to draw
            push bc
                ld a, (Lc893_draw_sprite_within_byte_offset)
                or a
                jr z, Lc9e4_no_shift_necessary
                ld b, a
                ; shifts the inverted byte to draw to the right, inserting 1s from the left:
Lc9de_mode3_inverted_shift_loop:
                srl d
                rr e
                djnz Lc9de_mode3_inverted_shift_loop
Lc9e4_no_shift_necessary:
                ld c, e
                ld a, (Lc894_mode3_tmp_storage)
                ld d, a
                ld a, (hl)
                ld (Lc894_mode3_tmp_storage), a  ; Store the byte to draw temporarily
                inc hl
                ld e, a
                ld a, (Lc893_draw_sprite_within_byte_offset)
                or a
                jr z, Lc9fc_no_shift_necessary
                ld b, a
                ; shifts the byte to draw to the right, inserting 0s from the left:
Lc9f6_mode3_shift_loop:
                srl d
                rr e
                djnz Lc9f6_mode3_shift_loop
Lc9fc_no_shift_necessary:
                ld a, c
                and (iy)  ; We keep the part of the background that corresponds to bits == 0 in the sprite to draw
                or e  ; We add the sprite to draw (only adding the 1s, keeping the background in the 0s)
                ld (iy), a  ; Draw
                inc iy
            pop bc
            dec c
            jr nz, Lc9d0_mode3_byte_loop
            ld d, b
            ld e, #ff
            ld a, (Lc893_draw_sprite_within_byte_offset)
            or a
            jr z, Lca1a
            ld b, a
Lca14:
            srl d
            rr e
            djnz Lca14
Lca1a:
            ld c, e
            dec hl
            ld d, (hl)
            inc hl
            ld e, 0
            ld a, (Lc893_draw_sprite_within_byte_offset)
            or a
            jr z, Lca2d
            ld b, a
Lca27:
            srl d
            rr e
            djnz Lca27
Lca2d:
            ld a, c
            and (iy)
            or e
            ld (iy), a
        pop af
        pop bc
        djnz Lca3b
        jr Lca3e_draw_complete
Lca3b:
        jp Ld015_drawing_mode3
Lca3e_draw_complete:
        ; If we are not within the interrupt, reenable them
        ld a, (L747c_within_interrupt_flag)
        and 128
        jr nz, Lca46_no_interrupt_reeneable
        ei
Lca46_no_interrupt_reeneable:
    pop af
    pop bc
    pop de
    pop hl
    pop iy
    pop ix
    ret


; --------------------------------
; Calculate render buffer pixel row pointers, and writes them to "L6664_row_pointers"
; Input:
; - hl: (hl + 1) contains the number of rows to calculate
Lca4f_calculate_pixel_row_pointers:
    push hl
    push de
    push bc
    push af
        inc hl
        ld b, (hl)
        ld hl, L6664_row_pointers
        ld de, L5cbc_render_buffer
Lca5b:
        ld (hl), e
        inc hl
        ld (hl), d
        inc hl
        ; de += SCREEN_WIDTH
        ld a, e
        add a, SCREEN_WIDTH
        ld e, a
        ld a, d
        adc a, 0
        ld d, a
        djnz Lca5b
    pop af
    pop bc
    pop de
    pop hl
    ret


; --------------------------------
; Temporary data for method Lca70_draw_sprite_from_ix_to_iy
Lca6e_x_offset_tmp:
    dw 0


; --------------------------------
; Draws a sprite from pointers in "iy" to pointers in "ix" with an offset
; Input:
; - hl: ptr to sprite attributes: w, h
; - ix: ptr to the row data of the sprite
; - iy: ptr to row pointers where to draw
; - a: x_offset (in bytes, applies to both source and target)
Lca70_draw_sprite_from_ix_to_iy:
    push ix
    push iy
    push hl
    push de
    push bc
    push af
        ld (Lca6e_x_offset_tmp), a  ; store the x_offset
        ld c, (hl)
        ld a, c
        inc hl
        ld b, (hl)
Lca7f_row_loop:
        push bc
            ld bc, (Lca6e_x_offset_tmp)  ; restore the x_offset
            ld l, (iy)
            ld h, (iy + 1)  ; get target pointer
            add hl, bc
            ex de, hl
            inc iy
            inc iy
            ld l, (ix)
            ld h, (ix + 1)  ; get source pointer
            add hl, bc
            inc ix
            inc ix
            ld c, a
            ldir
        pop bc
        djnz Lca7f_row_loop
    pop af
    pop bc
    pop de
    pop hl
    pop iy
    pop ix
    ret


; --------------------------------
; Checks is an object has crushed the player.
Lcaaa_check_if_object_crushed_player:
    push ix
    push hl
    push de
    push bc
        xor a
        ld (L7474_check_if_object_crushed_player_flag), a
        ld bc, (L6b28_player_radius)
        dec bc
        ld ix, (L6ad1_current_area_objects)
        ld a, (L6ad0_current_area_n_objects)
        or a
        call nz, Lcad5_check_if_object_crushed_player_internal
        ld ix, (L7463_global_area_objects)
        ld a, (L7465_global_area_n_objects)
        or a
        call nz, Lcad5_check_if_object_crushed_player_internal
        xor a
Lcacf:
    pop bc
    pop de
    pop hl
    pop ix
    ret


; --------------------------------
; Checks if an object from a given object list has crushed the player.
; Input:
; - ix: ptr to objects.
; - a: number of objects to check.
; - bc: player radius
Lcad5_check_if_object_crushed_player_internal:
Lcad5_check_if_object_crushed_player_internal_object_loop:
    push af
        ; See if this object needs to be checked:
        bit 4, (ix + OBJECT_TYPE_AND_FLAGS)
        jp z, Lcb60_next_object
        ; Mark that we have already checked this object, only if the 4th bit
        ; is set again to 1 by some game logic, the object will be checked again.
        res 4, (ix + OBJECT_TYPE_AND_FLAGS)
        ld de, (L6aad_player_current_x)
        ld h, (ix + OBJECT_X)
        call Lcb6d_hl_eq_h_times_64
        or a
        sbc hl, bc  ; hl = (object x * 64 - bc)
        or a
        sbc hl, de  ; hl = (object x * 64) - (bc + player x)
        jp p, Lcb60_next_object  ; no collision
        ; collision in x not ruled out
        ld a, (ix + OBJECT_X)
        add a, (ix + OBJECT_SIZE_X)
        ld h, a
        call Lcb6d_hl_eq_h_times_64
        add hl, bc
        or a
        sbc hl, de
        jp m, Lcb60_next_object  ; no collision
        ; Collision in the x axis:
        ld de, (L6ab1_player_current_z)
        ld h, (ix + OBJECT_Z)
        call Lcb6d_hl_eq_h_times_64
        or a
        sbc hl, bc
        or a
        sbc hl, de
        jp p, Lcb60_next_object
        ; collision in z not ruled out
        ld a, (ix + OBJECT_Z)
        add a, (ix + OBJECT_SIZE_Z)
        ld h, a
        call Lcb6d_hl_eq_h_times_64
        add hl, bc
        or a
        sbc hl, de
        jp m, Lcb60_next_object
        ; Collision in the x and z axes:
        ld de, (L6aaf_player_current_y)
        ld h, (ix + OBJECT_Y)
        call Lcb6d_hl_eq_h_times_64
        or a
        sbc hl, de
        jp p, Lcb60_next_object
        ; collision in y not ruled out
        ld a, (L6ab9_player_height)
        dec a
        add a, (ix + OBJECT_Y)
        add a, (ix + OBJECT_SIZE_Y)
        ld h, a
        call Lcb6d_hl_eq_h_times_64
        or a
        sbc hl, de
        jp m, Lcb60_next_object
        ; Collision in the x, y and z axes:
        ; Player insersects with a game object, trigger crushed game over!
        ld a, GAME_OVER_REASON_CRUSHED
        ld (L7479_current_game_state), a
        ld hl, 0
        ld (L746c_game_flags), hl
        call Lc87b_fade_out
        pop hl  ; pop af
    pop hl  ; cancel the "call" to this method
    jp Lcacf
Lcb60_next_object:
        ld e, (ix + OBJECT_SIZE)
        ld d, 0
        add ix, de
    pop af
    dec a
    jp nz, Lcad5_check_if_object_crushed_player_internal_object_loop
    ret


; --------------------------------
; Note: This method is repeated! "La9de_hl_eq_h_times_64" does the same!
; input:
; - h
; output:
; - hl = h * 64
Lcb6d_hl_eq_h_times_64:
    ld l, 0
    srl h
    rr l
    srl h
    rr l
    ret


; --------------------------------
; Effect for falling from a large height:
; - lose 5 strength
; - if strength reches 0, game over
; - It also plays 2 sfx (falling, and landing), and does a visual fade out effect for the fall
Lcb78_fall_from_height:
    push af
        xor a
        ld (L6ab6_player_pitch_angle), a
        ld a, SFX_FALLING
        ld (L747a_requested_SFX), a
        di
        ; Lose 5 strength
        ld a, (L6b0a_current_strength)
        sub 5
        jp p, Lcb91_sirvived_fall
        ; Strength reached 0, we die because of the fall!
        ld a, GAME_OVER_REASON_FATAL_FALL
        ld (L7479_current_game_state), a
        xor a
Lcb91_sirvived_fall:
        ld (L6b0a_current_strength), a
        ei
        call Lc87b_fade_out
        ld a, 1
        ld (L7477_render_buffer_effect), a  ; fade in effect
        ld a, SFX_THROW_ROCK_OR_LAND
        ld (L747a_requested_SFX), a
    pop af
    ret


; --------------------------------
; Checks if the player is not standing on any platform, and must fall.
; If the height the player falls is too hight, cause damage. Otherwise,
; just update player y.
Lcba4_check_for_player_falling:
    push hl
    push de
    push af
        ; We mark that this method has already been called:
        xor a
        ld (L7475_call_Lcba4_check_for_player_falling_flag), a
        ld hl, (L6aad_player_current_x)
        ld (L7456_player_desired_x), hl
        ld hl, (L6ab1_player_current_z)
        ld (L745a_player_desired_z), hl
        ld hl, (L6aaf_player_current_y)
        push hl
            ld h, a
            ld l, a
            ld (L7458_player_desired_y), hl  ; target going all the way down tot he floor
            inc a
            ld (L6abe_use_eye_player_coordinate), a
            ld a, (L6ab9_player_height)
            dec a
            ld e, l
            ld d, a
            srl d
            rr e
            srl d
            rr e  ; de = player height * 64
            push de
                ld hl, (L6aaf_player_current_y)
                or a
                sbc hl, de  ; subtract player height * 64 (feet coordinate)
                ld (L6aaf_player_current_y), hl
                ; Move player down until collision:
                call La5d9_move_player
                xor a
                ld (L6abe_use_eye_player_coordinate), a
                ld de, (L6aaf_player_current_y)
                sbc hl, de
                add hl, hl
                add hl, hl
            pop de
            cp h
            jr nz, Lcbf5_falling
            ; Not falling
        pop hl
        ld (L6aaf_player_current_y), hl
        jr Lcc15
Lcbf5_falling:
            ; Update game flags to trigger compass redraw, etc.
            ld a, (L746c_game_flags)
            or #14
            ld (L746c_game_flags), a
            ; Check if we fell from very high, to cause damage:
            ld a, (L6aba_max_falling_height_without_damage)
            cp h
        pop hl
        jp p, Lcc08_regular_fall
        ; Falling from high altitude, damage!
        call Lcb78_fall_from_height
Lcc08_regular_fall:
        ld hl, (L6aaf_player_current_y)
        ld a, l
        and #c0  ; clear the decimal part
        or #20  ; add "0.5"
        ld l, a
        add hl, de  ; add player height * 64 (we had subtracted it above)
        ld (L6aaf_player_current_y), hl
Lcc15:
    pop af
    pop de
    pop hl
    ret


; --------------------------------
; Draws a "viewport sprite" to the game viewport:
; - Viewport sprites are special and have:
;   - a buffer to save the background they overwrite
;   - 8 versions of the sprite and "and mask", offset 0, 1, 2, ..., 7 pixels to the right
; - This method, saves the background in the buffer, and draws the sprite
; - The bit 7 of the sprite height is a flag indicating whether the sprite overwrites background,
;   or if it flips the bits in the background when drawing (xor).
; - Sprite is drawn starting from the bottom and moving up the screen.
; Input:
; - hl: pointer to sprite data
Lcc19_draw_viewport_sprite_with_offset:
    push ix
    push iy
    push hl
    push de
    push bc
    push af
        ld bc, 6
        ld de, L76c2_buffer_sprite_x
        ldir  ; Copy x, y, width, height, buffer ptr
        ld d, h
        ld e, l
        ld bc, 16
        add hl, bc
        ex de, hl  ; hl = ptr to the masks ptrs, de = ptr to the frames ptrs
        xor a
        ld (L76c8_buffer_sprite_bytes_to_skip_at_start), a
        ld (L76ca_bytes_to_skip_after_row), a
        ld ix, L725c_videomem_row_pointers
        ld a, (L76c3_buffer_sprite_y)
          ; bc = 111 - y
        sub 111
        neg
        ld c, a
        bit 7, c
        jr z, Lcc48_positive
        dec b  ; when c is negative, make bc negative
Lcc48_positive:
        add ix, bc
        add ix, bc  ; ix = videomem row pointer where to start drawing
        ld a, (L76c2_buffer_sprite_x)
        dec a
        ld c, a
        srl c
        cp 192
        jr c, Lcc59
        set 7, c
Lcc59:
        sra c
        sra c  ; x = x coordinate / 8
        ld a, (L76c4_buffer_sprite_width)
        jp p, Lcc7a_positive_x_coordinate
        ; draw coordinate <= 0
        add a, c  ; a = x + width
        jp z, Lcd0b_draw_complete
        jp m, Lcd0b_draw_complete  ; drawing outside of the rendering buffer
        ld (L76c4_buffer_sprite_width), a  ; amount of bytes to draw per row
        ld a, c
        neg
        ld (L76c8_buffer_sprite_bytes_to_skip_at_start), a  ; |x coordinate|
        ld (L76ca_bytes_to_skip_after_row), a  ; |x coordinate|
        ld c, 0
        jr Lcc94_prepare_drawing_code

Lcc7a_positive_x_coordinate:
        ld b, a  ; b = width
        ld a, c  ; a = x coordinate / 8
        cp SCREEN_WIDTH
        jp nc, Lcd0b_draw_complete  ; drawing outside of the rendering buffer
        add a, b
        sub SCREEN_WIDTH
        jr z, Lcc94_prepare_drawing_code
        jr c, Lcc94_prepare_drawing_code  ; drawing outside of the rendering buffer
        ; too wide!  set width to SCREEN_WIDTH - x
        sub b
        neg
        ld (L76c4_buffer_sprite_width), a
        sub b  ; width - (SCREEN_WIDTH - x)
        neg
        ld (L76ca_bytes_to_skip_after_row), a  ; width - (SCREEN_WIDTH - x)

Lcc94_prepare_drawing_code:
        ; Here:
        ; hl = hl = ptr to the masks ptrs
        ; de = ptr to the frames ptrs
        ; c = x coordinate to draw to
        ld a, (L76c5_buffer_sprite_height)
        push hl
            ; Check if we want to invert the background or not:
            ld hl, #0518  ; machine code for "jr Lccf5"
            bit 7, a
            jr z, Lcca4
            and #7f  ; remove the background inversion flag
            ld hl, 0  ; machine code for "nop; nop"
Lcca4:
            ld (Lccee_selfmodifying), hl
        pop hl
        ld b, a
        push bc
            ld a, (L76c2_buffer_sprite_x)
            dec a
            and #07
            jr z, Lccba_zero_pixel_offset
            ; Get the proper sprite and mask ptrs:
            ; There are 8 versions of each mask and sprite (offset 1 more pixel to the right each time).
            add a, a
            ld b, 0
            ld c, a
            add hl, bc  ; and mask
            ex de, hl
                add hl, bc  ; sprite data
            ex de, hl
Lccba_zero_pixel_offset:
            ; read the actual pointers to and mask and sprite data:
            ; and mask:
            ld a, (hl)
            inc hl
            ld h, (hl)
            ld l, a
            ; sprite data:
            ld a, (de)
            inc de
            ld c, a
            ld a, (de)
            ld d, a
            ld e, c
            ld bc, (L76c8_buffer_sprite_bytes_to_skip_at_start)
            add hl, bc  ; and mask
            ex de, hl
                add hl, bc  ; sprite data
            ex de, hl
        pop bc
        ld iy, (L76c6_buffer_sprite_ptr)
Lccd1_drawing_loop_y:
        ; Here:
        ; b = height
        ; c = x coordinate
        ; iy = ptr to the buffer sprite ptr
        ; hl = ptr to and mask
        ; de = ptr to sprite data
        push bc
            push hl
                ld h, (ix + 1)
                ld l, (ix)
                dec ix
                dec ix
                ld b, 0
                add hl, bc  ; add x coordinate
                ld c, l
                ld b, h
            pop hl
            ld a, (L76c4_buffer_sprite_width)
Lcce6_drawing_loop_x:
            push af
                ld a, (bc)  ; read background byte
                ld (iy), a  ; save background to the buffer
                and (hl)  ; apply and mask
                ex de, hl
                    or (hl)  ; add the sprite
Lccee_selfmodifying:
                    jr Lccf5  ; this jr can be replaced by "nop; nop" above, depending on a flag
                    ; invert the pixels in the background
                    ld a, (de)  ; and mask
                    cpl  ; invert the mask
                    xor (iy)  ; invert background pixels
Lccf5:
                ex de, hl
                ld (bc), a  ; write resulting byte
                inc de
                inc hl
                inc bc
                inc iy
            pop af
            dec a
            jr nz, Lcce6_drawing_loop_x
            ld bc, (L76ca_bytes_to_skip_after_row)
            add hl, bc
            ex de, hl
            add hl, bc
            ex de, hl
        pop bc
        djnz Lccd1_drawing_loop_y
Lcd0b_draw_complete:
    pop af
    pop bc
    pop de
    pop hl
    pop iy
    pop ix
    ret


; --------------------------------
; Draws a sprite within the game viewport (making sure we do not
; overflow the viewport).
; - This method is usually used to restore the background after calling 'Lcc19_draw_viewport_sprite_with_offset',
;   as the background is stored in a viewport sprite, as if it were a regular sprite.
; - The sprite is drawn flipped upside down.
; - The attributes pointer points to: (x, y, width, height, data ptr)
; Input:
; - hl: sprite attributes pointer
Lcd14_restore_view_port_background_after_drawing_sprite:
    push ix
    push hl
    push de
    push bc
    push af
        ld b, (hl)
        ld ix, L725c_videomem_row_pointers
        inc hl
        ; calculate bc = 111 - (input hl + 1)
        ld a, (hl)
        sub 111
        neg
        ld c, a
        ld a, b
        inc hl
        ld b, 0
        bit 7, c
        jr z, Lcd2f_positive
        dec b
Lcd2f_positive:
        ; At this point:
        ; a = (input hl): x coordinate
        ; bc = 111 - (input hl + 1): y coordinate
        ; ix = L725c_videomem_row_pointers
        ; hl has incremented by 2 from input
        add ix, bc
        add ix, bc
        ld c, a
        dec c
        ld a, (hl)  ; width
        inc hl
        ld b, (hl)  ; height
        inc hl
        ld e, (hl)  ; pointer to the data to draw
        inc hl
        ld d, (hl)
        ex de, hl
        push af
            ld a, b
            and #7f  ; remove the "xor" bit flag from the sprite height.
            ld b, a
            ld a, c  ; x coordinate - 1
            srl c ; x coordinate / 2
            cp 192
            jr c, Lcd4b
            set 7, c
Lcd4b:
        pop af  ; a = width again
        sra c
        sra c  ; c = x coordinate / 8
        jp p, Lcd5d_positive_x_coordinate
        ; draw coordinate <= 0
        add a, c  ; a = x + width
        jr z, Lcd85_draw_complete
        jp m, Lcd85_draw_complete  ; drawing outside of the rendering buffer
        ld c, 0  ; x coordinate = 0
        jr Lcd6f_start_to_draw
Lcd5d_positive_x_coordinate:
        ld d, a  ; d = width
        ld a, c  ; a = x coordinate
        cp SCREEN_WIDTH
        jr nc, Lcd85_draw_complete  ; drawing outside of the rendering buffer
        add a, d  ; a = x + width
        sub SCREEN_WIDTH
        jr z, Lcd6e_width_ok
        jr c, Lcd6e_width_ok
        ; too wide!  set width to SCREEN_WIDTH - x
        sub d
        neg
        ld d, a
Lcd6e_width_ok:
        ld a, d
Lcd6f_start_to_draw:
        ; Draw "b" rows of "c" bytes each from hl to the row pointers in (ix) (bottom up)
        ; From each row only "a" bytes are copied.
        push bc
            ld d, (ix + 1)
            ld e, (ix)
            dec ix
            dec ix
            ld b, 0
            ex de, hl
                add hl, bc
            ex de, hl
            ld c, a
            ldir
        pop bc
        djnz Lcd6f_start_to_draw
Lcd85_draw_complete:
    pop af
    pop bc
    pop de
    pop hl
    pop ix
    ret


; --------------------------------
; Draw pointer in the center of the viewport
Lcd8c_draw_movement_center_pointer:
    push hl
    push de
    push bc
    push af
        ; position of the pointer:
        ld hl, L5cbc_render_buffer + 53 * SCREEN_WIDTH + 11
        ld de, SCREEN_WIDTH
        ld b, 3  ; top line of the pointer
Lcd98_loop:
        ld a, #01
        xor (hl)
        ld (hl), a
        add hl, de
        djnz Lcd98_loop

        ld a, #0e  ; right line
        xor (hl)
        ld (hl), a
        inc hl
        ld a, #e0  ; left line
        xor (hl)
        ld (hl), a
        dec hl
        ld b, 3  ; bottom line of the pointer
Lcdab_loop:
        add hl, de
        ld a, #01
        xor (hl)
        ld (hl), a
        djnz Lcdab_loop
    pop af
    pop bc
    pop de
    pop hl
    ret


; --------------------------------
; Auxiliary data for the gate animation routine.
Lcdb7_gate_row_type:  ; Some rows of the gate require masking, others not, etc.
    db #00
Lcdb8_gate_rows_left_to_draw:
    db #00
Lcdb9_rows_left_of_the_same_type:
    db #00
Lcdba_previous_gate_draw_y:
    db #00
Lcdbb_n_rows_to_clear_below:
    db #00
Lcdbc_gate_and_mask:
Lcdbc_gate_and_mask_left:
    db #00
Lcdbd_gate_and_mask_right:
    db #00
Lcdbe_gate_close_y_coordinates:
    ; Terminates when finding an "#ff"
    db  1,  2,  4,  7,  11,  16,  22,  29,  37,  48
    db 58, 69, 81, 93, 107, 112, 107, 112, 111, 112
    db #ff
Lcdd3_gate_row_gfx_horizontal_bar:
    db #20, #00, #04
    db #2a, #8b, #b5
    db #ab, #f0, #e5
    db #a0, #00, #05
Lcddf_gate_row_gfx:  ; Part in between horizontal bars
    db #00, #00
    db #00, #00
    db #80, #01
    db #80, #01
    db #00, #01
    db #80, #01
    db #00, #01
    db #00, #01
    db #00, #00
    db #00, #01
    db #00, #01
    db #80, #00
    db #80, #00
    db #00, #00
    db #80, #00
    db #80, #00
    db #80, #00
    db #80, #01
    db #80, #01
    db #80, #01
Lce07_gate_last_row_gfx:
    db #00, #00


; --------------------------------
; Visualization of the gate opening or closing over the game screen.
; This assumes the 3d view of the game has already been rendered to the render buffer.
; Input:
; - carry flag: set -> open gate, reset -> close gate
Lce09_gate_open_close_effect:
    push ix
    push iy
    push hl
    push de
    push bc
    push af
        jr c, Lce44_open_gate
        ; Close gate:
        ld ix, Lcdbe_gate_close_y_coordinates
Lce17_close_gate_loop:
        ld a, (ix)
        cp #ff  ; Sequence termination 
        jr z, Lce66_done
        ld c, a
        push af
            ld a, 2
            ld (L74a5_interrupt_timer), a
            call Lce6f_draw_gate
        pop af
        cp SCREEN_HEIGHT_IN_PIXELS
        ld a, SFX_MENU_SELECT
        call z, Lc4ca_play_SFX  ; This is when the gate bounces at the bottom of the screen.
Lce30_pause_loop:
        ld a, (L74a5_interrupt_timer)
        or a
        jr nz, Lce30_pause_loop
        inc ix
        ld a, (ix)
        cp #ff  ; Sequence termination
        ld a, SFX_GATE_CLOSE 
        call z, Lc4ca_play_SFX
        jr Lce17_close_gate_loop

Lce44_open_gate:
        ld c, SCREEN_HEIGHT_IN_PIXELS  ; start in the closed position
        call Lce6f_draw_gate
        ld b, 56
        ld c, 110
Lce4d_open_gate_loop:
        push bc
            ld a, 2
            ld (L74a5_interrupt_timer), a
            call Lce6f_draw_gate
Lce56_pause_loop:
            ld a, (L74a5_interrupt_timer)
            or a
            jr nz, Lce56_pause_loop
        pop bc
        dec c  ; move the gate up 2 pixels each frame
        dec c
        djnz Lce4d_open_gate_loop
        ld a, SFX_GAME_START
        call Lc4ca_play_SFX
Lce66_done:
    pop af
    pop bc
    pop de
    pop hl
    pop iy
    pop ix
    ret


; --------------------------------
; Renders the L5cbc_render_buffer to video memory, but drawing a game graphic on top.
; The gate is drawn starting at coordinate "c" (bottom row of the gate).
; Input:
; - c: y coordinates of the gate.
Lce6f_draw_gate:
    push ix
        ld a, c
        ld (Lcdb8_gate_rows_left_to_draw), a
        xor a
        ld b, a
        ld (Lcdbb_n_rows_to_clear_below), a  ; (Lcdbb_n_rows_to_clear_below) = 0
        ld a, (Lcdba_previous_gate_draw_y)  ; a = 0
        ; If the gate is being moved up, we set (Lcdbb_n_rows_to_clear_below) to how many pixels
        ; up it mved since last time (as we need to erase the bottom part of
        ; the previous version of the gate):
        sub c
        jr c, Lce83
        ld (Lcdbb_n_rows_to_clear_below), a
Lce83:
        ld a, c
        ld (Lcdba_previous_gate_draw_y), a
        ld de, #3ffc  ; and mask
        ld ix, L725c_videomem_row_pointers
        ld hl, L5cbc_render_buffer  ; Pointer to the pre-rendered background over which the gate will be drawn.
        or a
        jp z, Lcfe5_gate_draw_clear_bottom_rows  ; If no more pixels left to draw, go to clear bottom part.
        cp 1
        jr nz, Lcea7_draw_non_last_gate_row
        ; Draw last row of the gate:
        ld (Lcdb9_rows_left_of_the_same_type), a
        ld iy, Lce07_gate_last_row_gfx
        ld de, #7ffe  ; and mask of last row
        ld a, 5  ; Set row type to bottom row
        jr Lcf18_gate_draw_row
Lcea7_draw_non_last_gate_row:
        ; Determine the gfx to draw in this row:
        cp 16
        jr nc, Lcec1_non_first_16_rows
        ; One of the first 16 rows:
        dec a
        ld (Lcdb9_rows_left_of_the_same_type), a
        ld iy, Lcddf_gate_row_gfx
        sub 14
        jr z, Lcf18_gate_draw_row
        ; get the row gfx pointer:
        neg
        add a, a
        ld c, a
        add iy, bc
        ld a, 4
        jr Lcf18_gate_draw_row
Lcec1_non_first_16_rows:
        cp 20
        jr nc, Lcede_non_first_20_rows
        ; It's a horizontal bar:
        sub 15
        ld (Lcdb9_rows_left_of_the_same_type), a
        ld iy, Lcdd3_gate_row_gfx_horizontal_bar
        sub 4
        jr z, Lcf18_gate_draw_row
        neg
        ld c, a
        add a, a
        add a, c
        ld c, a
        add iy, bc
        ld a, 3  ; solid row type (horizontal bar)
        jr Lcf18_gate_draw_row
Lcede_non_first_20_rows:
        ; The rest of this code, does the same as above, just identifying which part
        ; of the gate we need to draw (horizontal bar, etc.), and get the correct pointer
        ; in "iy", and row type in "a".
        sub 19
Lcee0:
        cp 25
        jr c, Lcee8
        sub 24
        jr Lcee0
Lcee8:
        cp 21
        jr c, Lcf05
        sub 20
        ld (Lcdb9_rows_left_of_the_same_type), a
        ld iy, Lcdd3_gate_row_gfx_horizontal_bar
        sub 4
        jr z, Lcf18_gate_draw_row
        neg
        ld c, a
        add a, a
        add a, c
        ld c, a
        add iy, bc
        ld a, 1  ; solid row type (horizontal bar)
        jr Lcf18_gate_draw_row
Lcf05:
        ld (Lcdb9_rows_left_of_the_same_type), a
        ld iy, Lcddf_gate_row_gfx
        sub 20
        jr z, Lcf18_gate_draw_row
        neg
        add a, a
        ld c, a
        add iy, bc
        ld a, 2

Lcf18_gate_draw_row:
        ; Draws a row of the gate of different types, depending on "a" (row type).
        ; "de" at this point contains the and-mask for left/right bytes.
        ld (Lcdb7_gate_row_type), a
        ld (Lcdbc_gate_and_mask), de
Lcf1f:
        ld e, (ix)  ; Get ptr where to draw
        ld d, (ix + 1)
        inc ix  ; Next row
        inc ix
        ld a, (Lcdb7_gate_row_type)
        cp 1
        jr z, Lcf34_draw_solid_gate_row
        cp 3
        jr nz, Lcf76_draw_masking_gate_row
Lcf34_draw_solid_gate_row:
        ld bc, 24
        add hl, bc  ; advance "hl" (background ptr), since we are not using it in this row drawing iteration.
        push hl
            ; Draw the gate row pattern 8 times to make a full gate row.
            ; Draw from "iy" to "de":
            ld b, 8
Lcf3b_draw_solid_gate_row_loop:
            push iy
            pop hl
            ld c, 6  ; Make sure ldi does not modify 'b'.
            ldi
            ldi
            ldi
            djnz Lcf3b_draw_solid_gate_row_loop
        pop hl
        ld a, (Lcdb9_rows_left_of_the_same_type)
        dec a
        jr nz, Lcf6d
        ld a, (Lcdb7_gate_row_type)
        cp 1
        jr nz, Lcf5c
        ld a, 2
        ld c, 20
        jr Lcf60
Lcf5c:
        ld a, 4
        ld c, 14
Lcf60:
        ld (Lcdb7_gate_row_type), a
        ld a, c
        ld (Lcdb9_rows_left_of_the_same_type), a
        ld iy, Lcddf_gate_row_gfx
        jr Lcfd9_next_row
Lcf6d:
        ld (Lcdb9_rows_left_of_the_same_type), a
        ld c, 3
        add iy, bc
        jr Lcfd9_next_row

Lcf76_draw_masking_gate_row:
        ld b, 8  ; Gate is made out of 8 repeated horizontal blocks.
        ; Gate is read from (iy) [2 bytes], background from (hl), and we draw to (de):
Lcf78_draw_masking_gate_row_loop:
        ; Get the background left pixel, masked:
        ld a, (Lcdbd_gate_and_mask_right)
        and (hl)
        or (iy)  ; add the gate byte
        ld (de), a  ; draw it
        inc hl
        inc de
        ; Draw second byte as is (no need to mask, as it's in between gate bars):
        ld c, 4  ; make sure b is not modified
        ldi
        ; Get the background right pixel, masked:
        ld a, (Lcdbc_gate_and_mask_left)
        and (hl)
        or (iy + 1)
        ld (de), a  ; add the gate byte
        inc hl  ; draw it
        inc de
        djnz Lcf78_draw_masking_gate_row_loop

        ld a, (Lcdb7_gate_row_type)
        cp 5
        jr z, Lcfe5_gate_draw_clear_bottom_rows
        ld a, (Lcdb9_rows_left_of_the_same_type)
        dec a
        jr nz, Lcfd2
        ld a, (Lcdb7_gate_row_type)
        cp 4
        jr nz, Lcfb8
        ld de, 32766  ; #7ffe
        ld (Lcdbc_gate_and_mask_left), de
        ld a, 5
        ld (Lcdb7_gate_row_type), a
        ld iy, Lce07_gate_last_row_gfx
        jr Lcfd9_next_row
Lcfb8:
        ld a, (Lcdb8_gate_rows_left_to_draw)
        ld c, 3
        cp 21
        jr c, Lcfc3
        ld c, 1
Lcfc3:
        ld a, 4
        ld (Lcdb9_rows_left_of_the_same_type), a
        ld a, c
        ld (Lcdb7_gate_row_type), a
        ld iy, Lcdd3_gate_row_gfx_horizontal_bar
        jr Lcfd9_next_row
Lcfd2:
        ld (Lcdb9_rows_left_of_the_same_type), a
        inc iy
        inc iy
Lcfd9_next_row:
        ld a, (Lcdb8_gate_rows_left_to_draw)
        dec a
        jr z, Lcfe5_gate_draw_clear_bottom_rows
        ld (Lcdb8_gate_rows_left_to_draw), a
        jp Lcf1f
Lcfe5_gate_draw_clear_bottom_rows:
        ; Clear any rows below from any previous version of the gate that
        ; was drawn at a lower coordinate:
        ld a, (Lcdbb_n_rows_to_clear_below)
        or a
        jr z, Lcffd_done
Lcfeb_clear_bottom_rows_loop:
        ; Copy one row directly from "hl" to screen:
        ld e, (ix)
        ld d, (ix + 1)
        inc ix
        inc ix
        ld bc, 24
        ldir
        dec a
        jr nz, Lcfeb_clear_bottom_rows_loop
Lcffd_done:
    pop ix
    ret


; --------------------------------
Ld000_character_draw_buffer_properties:
    db 2, 8, #80  ; width (in bytes), height, and-mask of last byte
    dw 16  ; 16 = 2 * 8 (size in bytes of each frame)
Ld005_character_draw_buffer:
    db #00, #00, #08, #00, #0c, #00, #fe, #00, #ff, #00, #fe, #00, #0c, #00, #08, #00


; --------------------------------
; Draws a string of text to screen.
; Input:
; - d: string length
; - e: x offset
; - hl: ptr to a text string (prefixed by 0 / 1):
;       If prefix is 1, text is offset 5 pixels to the right.
;       This is useful for centering text that has an odd length.
; - ix: Pointer to the sequence of row pointers where to draw each row.
Ld015_draw_string_without_erasing:
    ; This is like "Ld01c_draw_string", but it uses drawing mode 3 in
    ; the call to "Lc895_draw_sprite_to_ix_ptrs", which means that
    ; we do not erase the background when drawing.
    push de
    push bc
        ld c, d  ; c = string length
        ld d, 128  ; set drawing mode 3
        jr Ld021_draw_string_continue
Ld01c_draw_string:
    push de
    push bc
        ld c, d  ; c = string length
        ld d, 0
Ld021_draw_string_continue:
        push hl
        push af
            ld a, (hl)
            inc hl
            or a
            jr z, Ld04e_no_indent
            dec c  ; length-- (the first was just the length)
            push hl
                ; Clear the character draw buffer:
                ld hl, Ld005_character_draw_buffer
                ld b, 16
                xor a
Ld030_clear_loop:
                ld (hl), a
                inc hl
                djnz Ld030_clear_loop

                ld hl, Ld000_character_draw_buffer_properties
                call Lc895_draw_sprite_to_ix_ptrs
                ld a, c
                sla a
                sla a
                sla a
                add a, c  ; a = length * 9  (each character is drawn 9 pixels to the right of the previous)
                push de
                    add a, e
                    ld e, a  ; e = length * 9 + x_offset
                    call Lc895_draw_sprite_to_ix_ptrs
                pop de
                ld a, 5
                add a, e
                ld e, a  ; x_offset += 5 (indent)
            pop hl
Ld04e_no_indent:
            ld b, c  ; b = length
Ld04f_character_loop:
            push bc
            push hl
                push de
                    ld c, d  ; 0 or 128 (depending on whether Ld015 or Ld01c_draw_string was called)
                    ld a, (hl)  ; get the next character to draw
                    sub ' '  ; get the index of the character
                    ld l, a
                    ld h, 0
                    add hl, hl
                    add hl, hl
                    add hl, hl
                    ld de, L7b47_font
                    add hl, de  ; hl = L7b47_font + a * 8

                    ; Write the character in the character draw buffer:
                    ld de, Ld005_character_draw_buffer
                    ld b, 8
Ld065_character_inner_draw_loop:
                    ld a, (hl)
                    ld (de), a
                    inc de
                    inc de  ; We skip 2 bytes in the buffer, since the buffer is 16*8 pixels,
                            ; but we are drawing an 8*8 character.
                    inc hl
                    djnz Ld065_character_inner_draw_loop
                    ld hl, Ld000_character_draw_buffer_properties
                pop de
                call Lc895_draw_sprite_to_ix_ptrs
                ld a, e
                add a, 9
                ld e, a  ; x_offset += 9 (next character)
            pop hl
            pop bc
            inc hl
            ; next character
            djnz Ld04f_character_loop
        pop af
        pop hl
    pop bc
    pop de
    ret


; --------------------------------
    db #c9  ; Unused? could be a left-over "ret".


; --------------------------------
Ld082_area_reference_start
Ld082_n_areas:
    db 39  ; Number of areas
Ld083_game_version:
    dw #22fa  ; Game version ID
Ld085_initial_area_id:
    db #02
Ld086_initial_player_object:  ; player start coordinates are taken from this object
    db #01
Ld087_starting_strength:
    db #10
Ld088_texture_patterns:  ; each texture has 4 bytes (to repeat vertically)
    db #00, #00, #00, #00
    db #ff, #ff, #ff, #ff
    db #dd, #77, #dd, #77
    db #aa, #55, #aa, #55
    db #88, #22, #88, #22
    db #55, #ff, #aa, #ff
    db #aa, #55, #55, #aa
    db #cc, #33, #cc, #33
    db #55, #55, #aa, #aa
    db #ff, #55, #ff, #aa
    db #ff, #ff, #ff, #ff
    db #77, #dd, #77, #dd
    db #aa, #aa, #55, #55
    db #33, #cc, #33, #cc
    db #22, #88, #22, #88

Ld0c4:  ; Unused?
    dw #01d5
Ld0c6_global_rules_offset:
    dw Ld11f_global_rules - Ld082_area_reference_start

    ; Game configuration parameters:
Ld0c8_speed_when_crawling:
    db #1e
Ld0c9_speed_when_walking:
    db #3c
Ld0ca_speed_when_running:
    db #f0
Ld0cb_n_sprits_that_must_be_killed:
    db #1a
Ld0cc_max_failling_height_in_room_units:
    db #02
Ld0cd_max_climbable_height_in_room_units:
    db #01
Ld0ce_yaw_rotation_speed:
    db #02
Ld0cf_keyboard_hold_delays:
    db #01, #01  ; Delay for the first key repeat if you hold the key, and delay for all repeats after that.

; - 39 16bit offsets (39 = (Ld082_n_areas)).
; - Each offset defines the start of a data blck with "Ld082_area_reference_start + offset".
Ld0d1_area_offsets:
    dw Ld169_area_1 - Ld082_area_reference_start
    dw Ld2be_area_ff - Ld082_area_reference_start
    dw Ld6c2_area_2 - Ld082_area_reference_start
    dw Ld8cf_area_3 - Ld082_area_reference_start
    dw Ld973_area_4 - Ld082_area_reference_start
    dw Lda83_area_5 - Ld082_area_reference_start
    dw Ldb5b_area_6 - Ld082_area_reference_start
    dw Ldc74_area_7 - Ld082_area_reference_start
    dw Ldcd8_area_8 - Ld082_area_reference_start
    dw Ldddb_area_9 - Ld082_area_reference_start
    dw Lde47_area_10 - Ld082_area_reference_start
    dw Lde9f_area_11 - Ld082_area_reference_start
    dw Ldf1e_area_12 - Ld082_area_reference_start
    dw Ldfad_area_13 - Ld082_area_reference_start
    dw Le024_area_14 - Ld082_area_reference_start
    dw Le090_area_15 - Ld082_area_reference_start
    dw Le1f3_area_22 - Ld082_area_reference_start
    dw Le48c_area_24 - Ld082_area_reference_start
    dw Le539_area_21 - Ld082_area_reference_start
    dw Le721_area_17 - Ld082_area_reference_start
    dw Le813_area_19 - Ld082_area_reference_start
    dw Le86c_area_27 - Ld082_area_reference_start
    dw Le8a3_area_28 - Ld082_area_reference_start
    dw Le903_area_29 - Ld082_area_reference_start
    dw Le953_area_49 - Ld082_area_reference_start
    dw Leb18_area_30 - Ld082_area_reference_start
    dw Leb75_area_31 - Ld082_area_reference_start
    dw Lebca_area_32 - Ld082_area_reference_start
    dw Lec68_area_33 - Ld082_area_reference_start
    dw Lecd0_area_35 - Ld082_area_reference_start
    dw Led69_area_37 - Ld082_area_reference_start
    dw Leec2_area_36 - Ld082_area_reference_start
    dw Lef4a_area_38 - Ld082_area_reference_start
    dw Lf035_area_40 - Ld082_area_reference_start
    dw Lf0ad_area_41 - Ld082_area_reference_start
    dw Lf0f5_area_42 - Ld082_area_reference_start
    dw Lf12c_area_43 - Ld082_area_reference_start
    dw Lf203_area_44 - Ld082_area_reference_start
    dw Lf2c4_area_46 - Ld082_area_reference_start

; The global rules are made out of a collection of "scripts":
; - The first byte is the number of "scripts".
; - Each script follows:
;   - First byte is the size of the script in bytes (not including the size)
;   - Then each script is made out of a collection of rules:
;     - The first byte of the rule is:
;       fftttttt:
;         - ff: determine which type of event will the rule match with:
;           - #00: movement
;           - #40: timer
;           - #80: stone throwing
;           - #c0: interact
;         - tttttt: rule type
;           - The size of each individual rule is determined by the type, and
;             the game determines it by checking the "L6b3c_rule_size_by_type" array.
;     - The rest of the bytes of the rule are the arguments of the rule.
;       - for example, rule type "1" had 3 bytes, encoding a 24 bit number that will
;         be added to the player score.
;     - Each "rule" is triggered if the current event that occurred (movement, interaction,
;       stone, timer) matches the flags. Some rules refer to objects, and the object the
;       player threw a rock to or interacted with is read from a global variable
;       from the game.
Ld11f_global_rules:
    db 7  ; Number of scripts
    ; Each script starts with the number of bytes remaining
    db  5,  #4e, #10, #01, #53, #02
    db 15,  #1e, #7f, #04, #88, #04, #89, #04, #8a, #2c, #05, #88, #05, #89, #05, #8a
    db  7,  #1e, #7e, #04, #8c, #2c, #05, #8c
    db 15,  #1e, #7d, #04, #90, #04, #91, #04, #92, #2c, #05, #90, #05, #91, #05, #92
    db  7,  #1e, #7c, #04, #94, #2c, #05, #94
    db 15,  #1e, #7b, #04, #96, #04, #97, #04, #98, #2c, #05, #96, #05, #97, #05, #98
    db  2,  #23, #00

    ; Each area block has the following structure:
    ; The area starts with an 8 bit header:
    ;   - area flags:
    ;       - 4 least significant bits are the sky texture number.
    ;       - most significant nibble are the floor texture number.
    ;   - n objects
    ;   - ID
    ;   - offset to rule data (2 bytes)
    ;   - scale
    ;   - attribute color
    ;   - area name
    ; - There is a special area "Ld2be_area_ff" that I suspect has global objects, but I have not checked.
    ; - Then there are as many objects as specified in the header.
    ; - Each object has the following structure:
    ;   - The byte 0 is the "type/state":
    ;     - 4 least significant bits are the object type.
    ;     - most significant nibble are the state/flags:
    ;       - bit 5: destroyed
    ;       - bit 6: invisible
    ;     - types: (see OBJECT_TYPE_* definitions at the beginning of this gile)
    ;   - bytes 1, 2, 3 are the x, y, z coordinates
    ;   - bytes 4, 5, 6 are the width, height and length
    ;   - byte 7: object ID
    ;   - byte 8: contains the length of the object
    ;   - bytes after that: additional data for the object:
    ;     - For geometric shapes (ID >= 10):
    ;       - first byte is their texture ID
    ;       - after that is vertices (3 bytes per vertex: x, y, z)
    ;     - For cubes (ID = 1), they have 3 bytes, containing the texture IDs for each of the 6 faces (2 per byte)
    ;     - For rectangles (ID = 3), they have 1 byte, with the texture ID of the two sides of the rectangle.
    ; - Some areas have a special object with ID "ff", that is not an object but contains a list of IDs of other objects.
    ; - After all the objects, there is a "rules" area.
Ld169_area_1:  ; WILDERNESS
    ; Header:
    db #81, 25, #01  ; flags, n objects, ID
    dw #0154  ; offset to rules
    db #01, #44, #00  ; scale, attribute, area name
    ; Objects (25 of them for this area):
    ; The first 9 bytes of an object are: type/state, x, y, z, dx, dy, dz, ID, size, the rest is extra info, specific fo each object.
    db #03, #1a, #00, #1a, #4c, #00, #4c, #03, #1a,  #10, #1c, #02, #12, #01, #2a, #1a, #22, #26, #1b, #32, #22, #10, #1b, #64, #13, #80  ; object 1
    db #01, #50, #00, #50, #10, #16, #10, #05, #0c,  #33, #00, #44  ; object 2
    db #01, #20, #00, #50, #10, #16, #10, #07, #0c,  #33, #00, #44  ; object 3
    db #01, #30, #00, #5a, #20, #12, #04, #0c, #0c,  #00, #00, #50  ; object 4
    db #03, #2b, #0f, #60, #01, #03, #00, #0d, #0a,  #10  ; object 5
    db #03, #23, #04, #60, #01, #03, #00, #0e, #0a,  #10  ; object 6
    db #03, #5c, #11, #60, #01, #03, #00, #0f, #0a,  #10  ; object 7
    db #03, #53, #04, #60, #01, #03, #00, #11, #0d,  #10, #12, #13, #d8  ; object 8
    db #c1, #3e, #00, #5e, #04, #01, #09, #10, #0c,  #bb, #90, #60  ; object 9
    db #01, #3e, #01, #5e, #04, #08, #01, #13, #0c,  #bb, #60, #d0  ; object 10
    db #ca, #3e, #01, #5e, #00, #07, #09, #15, #10,  #22, #3e, #01, #67, #3e, #08, #5e  ; object 11
    db #ca, #42, #01, #5e, #00, #07, #09, #16, #10,  #22, #42, #01, #67, #42, #08, #5e  ; object 12
    db #c0, #0e, #00, #7d, #00, #1c, #00, #1a, #09  ; object 13
    db #03, #44, #07, #5e, #01, #01, #00, #1c, #1d,  #60, #83, #16, #86, #11, #09, #86, #11, #0a, #86, #11, #0b, #83, #10, #83, #13, #83, #15, #9c, #08  ; object 14
    db #c0, #3f, #01, #5e, #00, #00, #00, #12, #09  ; object 15
    db #0d, #3e, #01, #5e, #04, #0b, #00, #02, #1c,  #01, #3e, #08, #5e, #40, #0c, #5e, #42, #08, #5e, #42, #01, #5e, #3e, #01, #5e, #12, #11, #0c  ; object 16
    db #c0, #25, #00, #62, #11, #1c, #00, #2a, #09  ; object 17
    db #c0, #7c, #00, #01, #00, #24, #00, #1b, #09  ; object 18
    db #c3, #06, #00, #6b, #01, #00, #01, #36, #0d,  #11, #12, #21, #8b  ; object 19
    db #c0, #3f, #0e, #68, #06, #1c, #00, #21, #09  ; object 20
    db #03, #3d, #00, #66, #06, #00, #04, #23, #0a,  #00  ; object 21
    db #c0, #23, #04, #60, #00, #00, #00, #19, #09  ; object 22
    db #01, #52, #03, #60, #03, #01, #02, #04, #0c,  #dd, #aa, #99  ; object 23
    db #c0, #53, #04, #61, #00, #00, #00, #06, #09  ; object 24
    db #03, #00, #00, #66, #7f, #00, #09, #01, #10,  #00, #0c, #1f, #01, #60, #2f, #34  ; object 25
    ; ; Area rules: (0 rules in this area):
    db 0

Ld2be_area_ff:
    ; Header:
    db #00, 75, #ff  ; flags, n objects, ID
    dw #0403  ; offset to rules
    db #01, #00, #60  ; scale, attribute, area name
    ; Objects:
    db #01, #00, #00, #00, #7f, #02, #7f, #80, #0c,  #00, #40, #00
    db #01, #02, #3d, #02, #7b, #02, #7b, #81, #0c,  #00, #04, #00
    db #01, #7d, #02, #00, #02, #3d, #7f, #83, #0c,  #03, #00, #00
    db #01, #02, #02, #7d, #7b, #3d, #02, #85, #0c,  #00, #00, #02
    db #c0, #05, #02, #79, #00, #24, #00, #d6, #15,  #e2, #17, #dc, #04, #d3, #03, #e3, #01, #c1, #98, #3a, #00
    db #c0, #03, #02, #79, #00, #12, #00, #d7, #13,  #89, #1c, #9c, #01, #a3, #01, #81, #c8, #af, #00
    db #c0, #3e, #02, #7c, #00, #24, #00, #d8, #13,  #dc, #0a, #e2, #11, #e3, #01, #c1, #c0, #d4, #01
    db #c0, #79, #02, #79, #00, #36, #00, #d9, #13,  #dc, #0d, #e2, #19, #e3, #01, #c1, #f0, #49, #02
    db #c0, #79, #02, #79, #00, #24, #00, #da, #0f,  #9c, #03, #81, #f8, #24, #01
    db #c0, #79, #02, #3e, #00, #36, #00, #db, #09
    db #c0, #79, #02, #06, #00, #00, #00, #dc, #09
    db #c0, #79, #02, #06, #00, #36, #00, #dd, #09
    db #c0, #3e, #02, #03, #00, #00, #00, #de, #09
    db #c0, #06, #02, #06, #00, #12, #00, #df, #09
    db #c0, #05, #02, #06, #00, #00, #00, #e0, #09
    db #c0, #03, #02, #3e, #00, #12, #00, #e1, #09
    db #41, #44, #02, #02, #02, #1c, #7b, #86, #0c, #03, #00, #00
    db #41, #02, #1e, #02, #7b, #02, #7b, #8d, #0c, #00, #04, #00
    db #01, #00, #02, #00, #02, #3b, #7f, #82, #0c, #30, #00, #00
    db #41, #02, #1f, #74, #72, #01, #09, #87, #0c, #00, #88, #05
    db #01, #02, #02, #00, #7b, #3d, #02, #84, #0c, #00, #00, #20
    db #41, #02, #1a, #65, #2e, #06, #18, #c5, #0c, #55, #88, #77
    db #41, #02, #14, #5d, #10, #06, #18, #ae, #0c, #ff, #66, #99
    db #41, #02, #0e, #55, #10, #06, #18, #af, #0c, #55, #88, #77
    db #41, #02, #08, #4d, #10, #06, #18, #c3, #0c, #ff, #aa, #dd
    db #41, #02, #02, #45, #10, #06, #18, #c4, #0c, #55, #88, #77
    db #41, #30, #02, #02, #02, #3b, #7b, #c6, #0c, #03, #00, #00
    db #c0, #0a, #02, #02, #00, #00, #00, #c7, #09
    db #c0, #0a, #20, #7c, #00, #24, #00, #c8, #09
    db #41, #02, #02, #40, #3e, #1c, #3d, #c9, #0c, #55, #88, #77
    db #c0, #2f, #02, #38, #00, #36, #00, #ca, #09
    db #41, #02, #0c, #13, #01, #0a, #0a, #cb, #0e, #44, #ff, #55, #e2, #1f
    db #43, #03, #13, #14, #00, #02, #02, #cc, #0c, #20, #f0, #cb
    db #43, #03, #10, #14, #00, #02, #02, #cd, #0c, #20, #f0, #cb
    db #43, #03, #0d, #14, #00, #02, #02, #d2, #0c, #20, #f0, #cb
    db #43, #03, #10, #17, #00, #02, #02, #d3, #0c, #20, #f0, #cb
    db #43, #03, #13, #1a, #00, #02, #02, #d4, #0c, #20, #f0, #cb
    db #43, #03, #10, #1a, #00, #02, #02, #d5, #0c, #20, #f0, #cb
    db #43, #03, #0d, #1a, #00, #02, #02, #e4, #0c, #20, #f0, #cb
    db #c0, #41, #02, #60, #00, #12, #00, #e5, #09
    db #41, #02, #16, #38, #7b, #02, #0e, #e6, #0c, #00, #04, #00
    db #41, #02, #02, #46, #7b, #3b, #01, #e9, #0c, #00, #00, #02
    db #41, #02, #02, #36, #7b, #3b, #02, #ea, #0c, #00, #00, #20
    db #c0, #5e, #02, #7c, #00, #24, #00, #eb, #09
    db #c0, #22, #02, #02, #00, #00, #00, #ec, #09
    db #47, #07, #28, #07, #18, #08, #10, #88, #1a, #d6, #d6, #90, #06, #04, #12, #0c, #90, #7f, #85, #88, #85, #89, #85, #8a, #b0, #d7
    db #41, #07, #30, #07, #18, #04, #10, #89, #0e, #dd, #00, #66, #b0, #88
    db #46, #07, #34, #07, #18, #04, #10, #8a, #12, #d6, #d6, #90, #06, #06, #10, #0a, #b0, #88
    db #4b, #3d, #0a, #40, #04, #00, #01, #8c, #19, #11, #3d, #0a, #41, #41, #0a, #41, #3f, #0a, #40, #90, #7e, #85, #8c, #b0, #d7
    db #41, #43, #0f, #2f, #01, #0d, #07, #90, #16, #89, #11, #11, #90, #7d, #85, #90, #85, #91, #85, #92, #b0, #d7
    db #41, #44, #14, #2f, #05, #01, #07, #91, #0e, #e0, #66, #11, #b0, #90
    db #41, #48, #0f, #2f, #01, #05, #07, #92, #0e, #ee, #0b, #11, #b0, #90
    db #46, #18, #07, #3f, #05, #02, #0a, #94, #28, #a5, #a2, #00, #00, #01, #05, #01, #e2, #17, #dc, #04, #d3, #03, #c5, #94, #c5, #7c, #e3, #01, #c9, #1c, #c1, #c8, #af, #00, #85, #94, #85, #7c, #b0, #d7
    db #44, #31, #02, #3e, #02, #01, #02, #96, #1a, #fb, #eb, #11, #00, #01, #00, #01, #90, #7b, #85, #96, #85, #97, #85, #98, #b0, #d7
    db #46, #2e, #02, #3e, #03, #01, #02, #97, #12, #05, #af, #00, #01, #01, #03, #01, #b0, #96
    db #4a, #2a, #02, #3f, #04, #00, #00, #98, #12, #11, #2a, #02, #3f, #2e, #02, #3f, #b0, #96
    db #41, #38, #02, #38, #10, #10, #10, #8b, #0c, #ff, #77, #55
    db #41, #1d, #02, #1d, #08, #08, #08, #8e, #0c, #ff, #77, #55
    db #41, #5e, #30, #25, #1f, #02, #58, #8f, #0c, #dd, #ee, #77
    db #41, #3f, #02, #02, #3e, #30, #1b, #93, #0c, #aa, #99, #ee
    db #41, #6a, #02, #24, #11, #0a, #16, #95, #0c, #ee, #00, #99
    db #41, #68, #0c, #22, #15, #01, #1a, #99, #0c, #11, #ff, #11
    db #47, #3f, #0c, #38, #02, #04, #02, #9a, #10, #9d, #9d, #00, #01, #00, #01, #00
    db #46, #3f, #10, #38, #02, #02, #02, #9b, #14, #6a, #6a, #00, #01, #01, #01, #01, #d3, #fe, #e2, #10
    db #c1, #02, #02, #2d, #01, #17, #0b, #9c, #0c, #88, #55, #55
    db #c1, #03, #0c, #2d, #08, #01, #0b, #9d, #0c, #e0, #bb, #55
    db #c1, #0a, #02, #2d, #01, #0a, #0b, #9e, #0c, #ee, #00, #55
    db #49, #02, #02, #13, #18, #0c, #10, #9f, #10, #e8, #e7, #80, #08, #00, #10, #0c
    db #48, #02, #02, #23, #18, #0c, #30, #a0, #10, #87, #85, #e0, #07, #00, #11, #0c
    db #41, #5e, #30, #02, #1f, #02, #7b, #a1, #0c, #77, #ff, #dd
    db #41, #02, #30, #02, #1f, #02, #7b, #a2, #0c, #77, #ff, #dd
    db #41, #02, #21, #02, #1f, #02, #7b, #a3, #0c, #77, #ff, #dd
    db #41, #02, #12, #02, #1f, #02, #7b, #a4, #0c, #77, #ff, #dd
    db #41, #17, #09, #2c, #18, #01, #28, #a5, #0c, #11, #ee, #11
    db #41, #1d, #02, #30, #0d, #07, #20, #a6, #0c, #ff, #66, #cc
    ; Area rules:
    db #00

Ld6c2_area_2:  ; THE CRYPT
    ; Header:
    db #00, 24, #02  ; no floor/sky, 24 objects, room ID 2
    dw #020c  ; offset to rules
    db #13, #47, #01  ; scale, attribute, area name
    ; Objects:
    db #c0, #80, #81, #82, #83, #84, #85, #ff, #09  ; object 1 (????)
    db #c3, #7d, #02, #33, #00, #30, #18, #02, #0d,   #11, #12, #03, #01  ; object 2 (????)
    db #04, #27, #0c, #06, #50, #0e, #20, #03, #10,   #1e, #0e, #80, #00, #0a, #0e, #17  ; object 3 (coffin body, part 1)
    db #05, #0f, #0c, #06, #18, #0e, #20, #04, #10,   #18, #08, #e0, #00, #08, #0e, #18  ; object 4 (coffin body, part 2)
    db #04, #27, #1a, #06, #50, #02, #20, #05, #20,   #8d, #0d, #90, #00, #0a, #01, #17, #e2, #24, #c4, #07, #c4, #08, #c5, #05, #c5, #06, #dc, #0b, #e3, #01, #c4, #7b  ; object 5 (coffin lid when closed, part 1)
    db #05, #0f, #1a, #06, #18, #02, #20, #06, #12,   #89, #09, #d0, #00, #08, #02, #18, #f0, #05  ; object 6 (coffin lid when closed, part 2)
    db #c4, #2a, #1a, #06, #50, #20, #02, #07, #1e,   #d5, #d8, #90, #08, #00, #18, #02, #e2, #25, #c4, #05, #c4, #06, #c5, #07, #c5, #08, #e3, #01, #dc, #08  ; object 7 (coffin lid when open, part 1)
    db #c5, #12, #1a, #06, #18, #20, #02, #08, #12,   #98, #95, #d0, #08, #00, #18, #02, #f0, #07  ; object 8 (coffin lid when open, part 2)
    db #01, #28, #02, #5c, #30, #15, #18, #09, #0c,   #88, #00, #77  ; object 9 (chest when closed)
    db #06, #28, #17, #5c, #30, #07, #18, #0a, #39,   #9e, #9e, #80, #00, #07, #30, #11, #e2, #24, #c5, #09, #c5, #0a, #c4, #0c, #c4, #0e, #c4, #0f, #c4, #10, #c4, #11, #c4, #12, #ce, #01, #00, #c4, #13, #c4, #14, #c4, #15, #c4, #16, #ed, #e3, #01, #dc, #0b, #ce, #11, #01, #c4, #1c, #cd, #11  ; object 10 (chest lid when closed)
    db #c8, #28, #17, #74, #30, #18, #09, #0c, #2a,   #9e, #9e, #01, #00, #07, #30, #11, #e2, #25, #c5, #0c, #c5, #0e, #c5, #0f, #c5, #10, #c5, #11, #c5, #12, #c4, #09, #c4, #0a, #c5, #13, #c5, #1c, #e3, #01, #dc, #08  ; object 11 (chest lid when open)
    db #c1, #28, #02, #5c, #02, #15, #18, #0e, #0c,   #58, #a0, #77  ; object 12 (open chest wall side 1)
    db #c1, #56, #02, #5c, #02, #15, #18, #0f, #0c,   #85, #a0, #77  ; object 13 (open chest wall side 2)
    db #c1, #2a, #02, #5c, #2c, #15, #02, #10, #0c,   #00, #a0, #d7  ; object 14 (open chest wall, front)
    db #c1, #2a, #02, #72, #2c, #15, #02, #11, #0c,   #00, #a0, #79  ; object 15 (open chest wall, back)
    db #c1, #2a, #02, #5e, #2c, #01, #14, #12, #0c,   #00, #10, #00  ; object 16 (open chest bottom)
    db #c3, #3d, #03, #66, #0c, #00, #06, #13, #11,   #b0, #d4, #20, #01, #c5, #13, #f0, #d8  ; object 17 (key)
    db #01, #7c, #02, #33, #01, #30, #18, #17, #22,   #55, #aa, #aa, #ce, #01, #00, #e2, #15, #db, #25, #e2, #2b, #db, #25, #e2, #13, #ec, #e2, #1a, #dc, #0b, #c5, #17, #c4, #02  ; object 18 (door blocking the exit)
    db #c0, #02, #02, #6d, #00, #1a, #00, #01, #09  ; object 19 (exit)
    db #03, #02, #27, #6f, #00, #01, #01, #1b, #41,   #33, #89, #10, #ae, #10, #09, #8c, #10, #8c, #1e, #94, #20, #01, #9a, #94, #20, #02, #9a, #94, #20, #03, #9a, #94, #20, #04, #9a, #94, #20, #05, #9a, #94, #20, #06, #9a, #94, #20, #07, #9a, #94, #20, #08, #9a, #94, #20, #09, #9a, #94, #20, #0a, #9a, #87, #16, #20, #87, #31, #13  ; object 20 (????)
    db #c2, #00, #00, #00, #00, #00, #00, #7b, #09  ; object 21 (spirit)
    db #c6, #51, #03, #68, #04, #03, #08, #1c, #23,   #65, #62, #00, #00, #01, #04, #01, #e2, #17, #dc, #04, #d3, #03, #c5, #1c, #e3, #01, #ce, #12, #00, #c1, #98, #3a, #00, #cc, #12  ; object 22 (invisible piece of cheese in the chest)
    db #01, #6b, #02, #12, #0a, #0a, #0a, #1d, #0c,   #ff, #00, #55  ; object 23 (foot of coffin 1) 
    db #01, #11, #02, #12, #0a, #0a, #0a, #1e, #0c,   #ff, #00, #55  ; object 24 (foot of coffin 2)
    ; Area rules:
    db #00

Ld8cf_area_3:  ; CRYPT CORRIDOR
    ; I have only annotated the first few blocks above as an example (as it is a lot of work to do this by hand), all other blocks below are analogous.
    db #00, #0c, #03, #a3, #00, #08, #46, #02
    db #c0, #80, #8d, #82, #86, #84, #85, #ff, #0b, #a5
    db #a6, #03, #02, #02, #18, #00, #10, #08, #02, #0d, #11, #12, #02, #db, #c0, #02
    db #02, #1c, #00, #12, #00, #01, #09, #03, #02, #02, #58, #00, #10, #08, #03, #0d
    db #11, #12, #04, #db, #c0, #02, #02, #5c, #00, #12, #00, #04, #09, #03, #44, #02
    db #58, #00, #10, #08, #05, #0d, #11, #12, #05, #e1, #c0, #43, #02, #5c, #00, #36 
    db #00, #06, #09, #03, #44, #02, #18, #00, #10, #08, #07, #0d, #11, #12, #06, #e1 
    db #c0, #43, #02, #1b, #00, #36, #00, #08, #09, #c3, #1f, #02, #7d, #08, #10, #00 
    db #09, #0d, #11, #12, #07, #de, #c0, #22, #02, #7c, #00, #24, #00, #0a, #09, #01 
    db #1f, #02, #7c, #08, #10, #01, #0e, #22, #11, #11, #55, #ce, #02, #00, #e2, #15 
    db #db, #25, #e2, #2f, #db, #25, #e2, #13, #ec, #e2, #1a, #dc, #0b, #c5, #0e, #c4 
    db #09, #00

Ld973_area_4:  ; THE MOUSETRAP
    db #00, #11, #04, #0f, #01, #10, #47, #03
    db #c0, #80, #81, #82, #83, #84 
    db #85, #ff, #0c, #a2, #a3, #a4, #03, #7d, #02, #38, #00, #20, #10, #02, #0d, #11 
    db #12, #03, #04, #01, #38, #02, #38, #01, #1c, #10, #01, #0c, #99, #11, #11, #01 
    db #44, #02, #38, #01, #0d, #10, #03, #0c, #99, #dd, #11, #01, #39, #0f, #38, #0c 
    db #01, #10, #04, #0c, #99, #af, #11, #01, #30, #14, #08, #20, #01, #20, #06, #0c 
    db #aa, #de, #aa, #01, #30, #02, #0c, #20, #12, #01, #07, #0c, #66, #00, #ff, #01 
    db #30, #02, #23, #20, #12, #01, #08, #0c, #66, #00, #55, #06, #36, #15, #12, #08 
    db #02, #0c, #0a, #30, #26, #2a, #00, #00, #01, #08, #01, #c5, #0a, #c4, #0b, #c4 
    db #0c, #c4, #05, #c4, #09, #c4, #0d, #c4, #0e, #c4, #0f, #c4, #10, #c5, #06, #c5
    db #07, #c5, #08, #c5, #01, #c5, #03, #c5, #04, #f0, #d6, #c2, #00, #00, #00, #00
    db #00, #00, #0b, #09, #c2, #00, #00, #00, #00, #00, #00, #0c, #09, #c1, #2e, #16 
    db #4c, #01, #1c, #10, #05, #16, #99, #11, #11, #85, #05, #85, #09, #85, #0d, #85 
    db #0b, #b0, #d7, #c1, #2f, #23, #4c, #0c, #01, #10, #09, #0e, #99, #af, #11, #b0 
    db #05, #c1, #3a, #16, #4c, #01, #0d, #10, #0d, #0e, #99, #d1, #11, #b0, #05, #c1 
    db #30, #2d, #12, #20, #01, #20, #0e, #16, #aa, #de, #aa, #85, #0e, #85, #0f, #85 
    db #10, #85, #0c, #b0, #d7, #c1, #30, #1b, #16, #20, #12, #01, #0f, #0e, #66, #00 
    db #ff, #b0, #0e, #c1, #30, #1b, #2d, #20, #12, #01, #10, #0e, #66, #00, #55, #b0 
    db #0e, #00

Lda83_area_5:  ; LAST TREASURE
    db #00, #0c, #05, #d7, #00, #10, #47, #04
    db #c0, #80, #81, #82, #83, #84 
    db #85, #ff, #0a, #93, #03, #02, #02, #38, #00, #20, #10, #02, #0d, #11, #12, #03 
    db #06, #03, #4e, #35, #02, #0c, #06, #00, #04, #11, #99, #d4, #20, #02, #c5, #04 
    db #f0, #d8, #c1, #0b, #02, #02, #12, #0e, #12, #01, #17, #66, #77, #55, #c5, #01 
    db #c7, #06, #0a, #e3, #01, #dc, #0e, #e2, #18, #01, #1c, #10, #02, #12, #0d, #12
    db #03, #17, #aa, #99, #88, #c5, #03, #c7, #06, #0b, #e3, #01, #dc, #0e, #e2, #18
    db #03, #0b, #02, #02, #12, #0e, #00, #0d, #0a, #55, #03, #1c, #10, #02, #12, #0d  
    db #00, #0e, #0a, #88, #01, #33, #02, #69, #28, #11, #10, #0f, #0c, #88, #11, #dd  
    db #06, #33, #13, #69, #28, #04, #10, #10, #24, #7e, #7e, #80, #00, #04, #28, #0c  
    db #ce, #06, #01, #e2, #24, #dc, #0b, #c5, #10, #c4, #11, #c4, #18, #c4, #1c, #e3  
    db #01, #ec, #e2, #13, #c8, #33, #13, #79, #28, #10, #04, #11, #10, #7e, #7e, #8f  
    db #00, #04, #28, #0c, #c3, #4c, #13, #6f, #0b, #00, #06, #18, #11, #22, #d4, #20  
    db #08, #c5, #18, #f0, #d8, #c6, #36, #13, #6d, #05, #02, #09, #1c, #14, #ba, #b6  
    db #00, #00, #01, #05, #01, #c5, #1c, #f0, #d6, #00

Ldb5b_area_6:  ; TANTALUS
    db #00, #10, #06, #18, #01, #10, #47, #05
    db #c0, #80, #81, #82, #83, #84, #85, #ff, #0a, #8f, #03, #02, #02, #38  
    db #00, #20, #10, #02, #0d, #11, #12, #03, #08, #04, #27, #0c, #06, #3c, #0e, #20  
    db #03, #10, #1e, #1e, #80, #00, #0a, #0e, #17, #05, #0f, #0c, #06, #18, #0e, #20  
    db #04, #10, #18, #08, #e0, #00, #08, #0e, #18, #04, #27, #1a, #06, #3c, #02, #20  
    db #05, #20, #8d, #0d, #90, #00, #0a, #01, #17, #e2, #24, #c4, #07, #c4, #08, #c5  
    db #05, #c5, #06, #dc, #0b, #e3, #01, #c4, #7b, #05, #0f, #1a, #06, #18, #02, #20  
    db #06, #12, #8d, #09, #d0, #00, #08, #02, #18, #f0, #05, #c4, #2a, #1a, #06, #3c  
    db #20, #02, #07, #1e, #d5, #d8, #90, #08, #00, #18, #02, #e2, #25, #c5, #07, #c5  
    db #08, #c4, #05, #c4, #06, #e3, #01, #dc, #08, #c5, #12, #1a, #06, #18, #20, #02  
    db #08, #12, #98, #95, #d0, #08, #00, #18, #02, #f0, #07, #06, #62, #32, #6c, #08  
    db #02, #0c, #09, #14, #ba, #b6, #00, #00, #01, #08, #01, #c5, #09, #f0, #d6, #01
    db #0b, #02, #6b, #12, #0e, #12, #0a, #17, #66, #77, #55, #c5, #0a, #c7, #05, #01  
    db #e3, #01, #dc, #0e, #e2, #18, #c1, #1c, #10, #6b, #12, #0d, #12, #0b, #17, #aa  
    db #99, #88, #c5, #0b, #c7, #05, #03, #e3, #01, #dc, #0e, #e2, #18, #03, #1c, #10
    db #7d, #12, #0d, #00, #0c, #0a, #88, #03, #0b, #02, #7d, #12, #0e, #00, #0d, #0a  
    db #55, #01, #61, #02, #10, #02, #0a, #0d, #0f, #0c, #66, #00, #bb, #01, #0f, #02  
    db #0e, #02, #0a, #10, #12, #0c, #66, #00, #bb, #c2, #00, #00, #00, #00, #00, #00  
    db #7b, #09, #00

Ldc74_area_7:  ; BELENUS
    db #00, #06, #07, #63, #00, #10, #47, #06
    db #c0, #80, #81, #82, #83
    db #84, #85, #ff, #0c, #8b, #9f, #a0, #03, #38, #02, #02, #10, #20, #00, #02, #0d  
    db #11, #12, #03, #0a, #03, #38, #02, #7d, #10, #20, #00, #03, #0d, #11, #12, #08  
    db #01, #03, #7d, #02, #38, #00, #20, #10, #05, #0d, #11, #12, #16, #01, #07, #3c  
    db #12, #3c, #08, #08, #08, #04, #12, #d6, #d6, #00, #04, #04, #04, #04, #f0, #06  
    db #06, #3c, #1a, #3c, #08, #02, #08, #06, #16, #6d, #6d, #a0, #02, #02, #06, #06  
    db #c5, #04, #c5, #06, #f0, #d9, #00

Ldcd8_area_8:  ; POTHOLE
    db #00, #13, #08, #02, #01, #02, #46, #07
    db #c0  
    db #80, #00, #00, #00, #00, #00, #ff, #09, #01, #09, #02, #0a, #0a, #3b, #01, #02  
    db #0c, #00, #00, #20, #01, #07, #02, #01, #02, #3b, #17, #03, #0c, #30, #00, #00  
    db #01, #13, #02, #01, #01, #3b, #17, #04, #0c, #03, #00, #00, #01, #00, #02, #18  
    db #1a, #3d, #01, #05, #0c, #00, #00, #02, #c0, #0d, #02, #0b, #00, #00, #00, #01  
    db #09, #01, #02, #3d, #01, #18, #02, #17, #06, #0c, #00, #04, #00, #03, #0d, #02  
    db #0b, #02, #04, #00, #07, #0d, #11, #12, #07, #d8, #c3, #0f, #02, #18, #02, #04
    db #00, #08, #0d, #11, #12, #09, #c7, #c0, #0f, #02, #17, #00, #24, #00, #09, #09  
    db #03, #0d, #1c, #18, #02, #04, #00, #0b, #0d, #11, #12, #20, #de, #03, #0c, #29  
    db #18, #02, #04, #00, #0c, #0d, #11, #12, #2b, #de, #01, #0c, #1b, #17, #04, #01  
    db #01, #0f, #0c, #bb, #ee, #dd, #01, #0b, #28, #17, #04, #01, #01, #10, #0c, #bb  
    db #88, #dd, #c0, #0e, #0f, #17, #00, #24, #00, #12, #09, #c0, #0d, #1c, #17, #00  
    db #24, #00, #13, #09, #c0, #0c, #29, #17, #00, #24, #00, #14, #09, #01, #0f, #02  
    db #17, #02, #04, #01, #16, #2b, #dd, #99, #55, #ef, #1d, #11, #e2, #1d, #db, #32  
    db #e2, #27, #cc, #11, #ec, #e2, #1a, #dc, #0b, #c5, #16, #c4, #08, #c8, #09, #04  
    db #c7, #09, #02, #e3, #01, #d1, #02, #1c, #03, #11, #1d, #18, #01, #02, #00, #18
    db #11, #ff, #d4, #20, #04, #c5, #18, #f0, #d8, #00

Ldddb_area_9:  ; THE STEPS
    db #00, #05, #09, #6b, #00, #08, #07, #08
    db #c0, #80, #81, #82, #af, #84, #85, #ff, #15, #ae, #c3, #c4, #c5, #c6
    db #cb, #cc, #cd, #d2, #d4, #d5, #e4, #03, #06, #02, #02, #08, #10, #00, #02, #0d
    db #11, #12, #08, #09, #03, #06, #20, #7d, #08, #10, #00, #03, #0d, #11, #12, #0a  
    db #c7, #c3, #06, #02, #02, #08, #10, #00, #04, #20, #aa, #ef, #1d, #11, #e2, #1d  
    db #ec, #e2, #1a, #dc, #0b, #c5, #04, #c4, #02, #c8, #08, #16, #c7, #08, #08, #e3
    db #01, #06, #2a, #02, #28, #04, #01, #08, #05, #14, #a5, #ab, #00, #00, #01, #04  
    db #01, #c5, #05, #f0, #d6, #00

Lde47_area_10:  ; THE STEPS
    db #00, #05, #0a, #57, #00, #08, #07, #08
    db #c0, #80  
    db #81, #82, #84, #85, #ae, #ff, #14, #af, #c3, #c4, #c5, #c6, #cb, #cc, #d2, #d3
    db #d4, #e4, #03, #06, #02, #02, #08, #10, #00, #02, #0d, #11, #12, #09, #c8, #03
    db #06, #20, #7d, #08, #10, #00, #03, #0d, #11, #12, #0b, #c7, #03, #30, #02, #34  
    db #00, #10, #08, #04, #0d, #11, #12, #1b, #e1, #06, #2a, #02, #28, #04, #01, #08  
    db #06, #14, #a5, #ab, #00, #00, #01, #04, #01, #c5, #06, #f0, #d6, #00

Lde9f_area_11:  ; THE STEPS
    db #00, #06, #0b, #7e, #00, #08, #07, #08
    db #c0, #80, #81, #82, #84, #85, #ae, #ff, #13, #af  
    db #c3, #c4, #c5, #c6, #cb, #cc, #d2, #d4, #e4, #03, #06, #02, #02, #08, #10, #00
    db #02, #0d, #11, #12, #0a, #c8, #03, #06, #20, #7d, #08, #10, #00, #03, #0d, #11  
    db #12, #0c, #c7, #c3, #30, #02, #34, #00, #10, #08, #04, #0d, #11, #12, #1e, #e1  
    db #01, #2f, #02, #34, #01, #10, #08, #01, #28, #55, #11, #11, #ce, #05, #00, #e2  
    db #15, #db, #25, #e2, #38, #db, #25, #e2, #13, #ec, #e2, #1a, #dc, #0b, #c5, #01
    db #c4, #04, #c8, #1e, #03, #c7, #1e, #02, #06, #2a, #02, #28, #04, #01, #08, #08
    db #14, #a5, #ab, #00, #00, #01, #04, #01, #c5, #08, #f0, #d6, #00

Ldf1e_area_12:  ; THE STEPS
    db #00, #07, #0c, #8e, #00, #08, #07, #08
    db #c0, #80, #81, #82, #84, #85, #ae, #ff, #12, #af, #c3
    db #c4, #c5, #c6, #cb, #d2, #d3, #d4, #03, #06, #20, #7d, #08, #10, #00, #02, #0d
    db #11, #12, #0d, #c7, #03, #06, #02, #02, #08, #10, #00, #03, #0d, #11, #12, #0b
    db #c8, #c3, #30, #02, #34, #00, #10, #08, #04, #0d, #11, #12, #23, #e1, #03, #03
    db #03, #5d, #06, #03, #00, #01, #11, #20, #d4, #20, #09, #c5, #01, #f0, #d8, #01
    db #2f, #02, #34, #01, #10, #08, #08, #28, #ff, #11, #11, #ce, #04, #00, #e2, #15
    db #db, #25, #e2, #43, #db, #25, #e2, #13, #ec, #e2, #1a, #dc, #0b, #c5, #08, #c4
    db #04, #c8, #23, #01, #c7, #23, #02, #06, #2a, #02, #28, #04, #01, #08, #0c, #14
    db #a5, #ab, #00, #00, #01, #04, #01, #c5, #0c, #f0, #d6, #00

Ldfad_area_13:  ; THE STEPS
    db #00, #06, #0d, #76, #00, #08, #07, #08
    db #c0, #80, #81, #82, #84, #85, #ae, #ff, #11, #af, #c3, #c4
    db #c5, #c6, #cb, #cc, #e4, #03, #06, #02, #02, #08, #10, #00, #02, #0d, #11, #12
    db #0c, #c8, #03, #06, #20, #7d, #08, #10, #00, #03, #0d, #11, #12, #0e, #de, #c3
    db #30, #02, #34, #00, #10, #08, #04, #0d, #11, #12, #2c, #e1, #01, #2f, #02, #34
    db #01, #10, #08, #01, #22, #ff, #11, #11, #ce, #03, #00, #e2, #15, #db, #25, #e2
    db #4a, #db, #25, #e2, #13, #ec, #e2, #1a, #dc, #0b, #c5, #01, #c4, #04, #06, #2a
    db #02, #28, #04, #01, #08, #08, #14, #a5, #ab, #00, #00, #01, #04, #01, #c5, #08
    db #f0, #d6, #00

Le024_area_14:  ; LOOKOUT POST
    db #00, #06, #0e, #6b, #00, #10, #46, #09
    db #c0, #80, #81, #82, #83
    db #84, #85, #ff, #0b, #9f, #a0, #03, #38, #02, #02, #10, #20, #00, #02, #0d, #11
    db #12, #0d, #c8, #03, #34, #12, #7d, #0c, #22, #00, #03, #13, #11, #12, #01, #19
    db #1a, #1b, #32, #12, #0e, #04, #c3, #7d, #02, #38, #00, #20, #10, #05, #0d, #11
    db #12, #0f, #31, #c0, #3a, #02, #70, #00, #00, #00, #04, #09, #01, #7c, #02, #38
    db #01, #20, #10, #01, #22, #ff, #11, #11, #ce, #07, #00, #e2, #15, #db, #25, #e2
    db #33, #db, #25, #e2, #13, #ec, #e2, #1a, #dc, #0b, #c5, #01, #c4, #05, #00

Le090_area_15:  ; KERBEROS
    db #00, #17, #0f, #62, #01, #10, #07, #0a
    db #c0, #80, #81, #82, #83, #84, #85, #ff, #09
    db #03, #02, #02, #38, #00, #20, #10, #02, #0d, #11, #12, #0e, #db, #c3, #7d, #02
    db #38, #00, #20, #10, #01, #0d, #11, #12, #11, #d7, #05, #40, #12, #3c, #07, #04
    db #06, #03, #29, #da, #da, #18, #00, #02, #02, #04, #9f, #09, #9f, #0d, #89, #03
    db #ae, #03, #05, #85, #03, #85, #04, #85, #05, #84, #21, #85, #2f, #84, #01, #85
    db #32, #b0, #d7, #03, #47, #16, #40, #00, #04, #02, #04, #0a, #ff, #03, #47, #16
    db #3c, #00, #04, #02, #05, #0a, #ff, #05, #41, #12, #43, #06, #04, #06, #09, #1d
    db #9a, #9a, #18, #00, #02, #02, #04, #89, #02, #ae, #02, #05, #85, #09, #85, #0a
    db #85, #0b, #84, #22, #03, #47, #16, #47, #00, #04, #02, #0a, #0a, #55, #03, #47
    db #16, #43, #00, #04, #02, #0b, #0a, #55, #05, #41, #12, #35, #06, #04, #06, #0d
    db #1d, #9a, #9a, #18, #00, #02, #02, #04, #89, #04, #ae, #04, #05, #85, #0d, #85
    db #0e, #85, #0f, #84, #1a, #03, #47, #16, #39, #00, #04, #02, #0e, #0a, #55, #03
    db #47, #16, #35, #00, #04, #02, #0f, #0a, #55, #07, #49, #02, #37, #03, #09, #03
    db #16, #10, #26, #26, #00, #00, #00, #01, #01, #07, #5b, #02, #37, #03, #09, #03
    db #17, #10, #26, #26, #00, #02, #00, #03, #01, #07, #5b, #02, #44, #03, #09, #03
    db #18, #10, #26, #26, #00, #02, #02, #03, #03, #07, #49, #02, #44, #03, #09, #03
    db #19, #10, #26, #26, #00, #01, #02, #02, #03, #c7, #43, #0c, #35, #04, #06, #06
    db #1a, #10, #9a, #9a, #18, #01, #02, #03, #04, #c7, #42, #0c, #3c, #05, #06, #06
    db #21, #10, #da, #da, #18, #02, #02, #04, #04, #c7, #43, #0c, #43, #04, #06, #06
    db #22, #10, #9a, #9a, #18, #01, #02, #03, #04, #03, #7d, #02, #38, #00, #20, #10
    db #2f, #0a, #77, #c0, #0b, #02, #3e, #00, #12, #00, #31, #09, #02, #00, #00, #00
    db #00, #00, #00, #32, #09, #01, #47, #0b, #35, #18, #07, #14, #06, #0c, #88, #ee
    db #aa, #00

Le1f3_area_22:  ; LIFT SHAFT
    db #00, #2e, #16, #98, #02, #03, #45, #10
    db #c0, #80, #81, #82, #83, #00
    db #00, #ff, #09, #03, #02, #02, #10, #00, #06, #03, #02, #0d, #11, #12, #07, #db
    db #03, #7d, #03, #10, #00, #06, #04, #04, #0d, #11, #12, #18, #01, #03, #7d, #10
    db #10, #00, #06, #04, #05, #0d, #11, #12, #1d, #e5, #03, #7d, #1d, #10, #00, #06
    db #04, #06, #0d, #11, #12, #21, #df, #03, #7d, #2a, #10, #00, #06, #04, #07, #0d
    db #11, #12, #29, #e5, #01, #75, #02, #0e, #08, #09, #08, #08, #0c, #dd, #55, #88
    db #c0, #7b, #02, #12, #00, #36, #00, #09, #09, #c0, #7c, #10, #12, #00, #36, #00
    db #0a, #09, #c0, #7c, #1d, #12, #00, #36, #00, #0b, #09, #c0, #7c, #2b, #12, #00
    db #36, #00, #0c, #09, #c0, #02, #02, #11, #00, #12, #00, #01, #09, #01, #02, #02
    db #0a, #7b, #3b, #02, #0d, #0c, #00, #00, #20, #c1, #75, #0f, #0e, #08, #09, #08
    db #0e, #0c, #dd, #55, #88, #c1, #75, #1c, #0e, #08, #09, #08, #0f, #0c, #dd, #55
    db #88, #c1, #75, #29, #0e, #08, #09, #08, #10, #0c, #dd, #55, #88, #c6, #76, #02
    db #1e, #06, #05, #08, #11, #10, #8e, #8e, #ff, #02, #02, #04, #06, #c6, #76, #0f
    db #1e, #06, #05, #08, #12, #10, #8e, #8e, #ff, #02, #02, #04, #06, #c6, #76, #1c
    db #1e, #06, #05, #08, #13, #10, #8e, #8e, #ff, #02, #02, #04, #06, #06, #76, #29
    db #1e, #06, #05, #08, #14, #10, #8e, #8e, #ff, #02, #02, #04, #06, #01, #77, #38
    db #12, #06, #01, #10, #16, #0c, #11, #88, #88, #0a, #79, #2e, #22, #00, #0b, #00
    db #17, #10, #11, #79, #2e, #22, #79, #39, #22, #ca, #79, #32, #12, #00, #07, #00
    db #19, #10, #11, #79, #32, #12, #79, #39, #12, #ca, #79, #21, #22, #00, #18, #00
    db #1a, #10, #11, #79, #21, #22, #79, #39, #22, #ca, #79, #14, #22, #00, #25, #00
    db #1b, #10, #11, #79, #14, #22, #79, #39, #22, #ca, #79, #07, #22, #00, #32, #00
    db #1c, #10, #11, #79, #07, #22, #79, #39, #22, #ca, #79, #25, #12, #00, #14, #00
    db #1d, #10, #11, #79, #25, #12, #79, #39, #12, #ca, #79, #18, #12, #00, #21, #00
    db #1e, #10, #11, #79, #18, #12, #79, #39, #12, #0a, #79, #0b, #12, #00, #2e, #00
    db #1f, #10, #11, #79, #0b, #12, #79, #39, #12, #c1, #0e, #0a, #17, #04, #04, #04
    db #20, #0f, #99, #99, #99, #92, #31, #01, #07, #6f, #02, #20, #05, #02, #04, #21
    db #10, #fe, #fe, #00, #01, #01, #04, #03, #06, #6f, #04, #20, #05, #02, #04, #23
    db #10, #fe, #fe, #90, #03, #02, #04, #03, #c7, #76, #02, #20, #05, #02, #04, #24
    db #10, #fe, #fe, #00, #01, #01, #04, #03, #c6, #76, #04, #20, #05, #02, #04, #26
    db #10, #fe, #fe, #90, #03, #02, #04, #03, #03, #6f, #02, #20, #00, #04, #04, #27
    db #24, #00, #2e, #1d, #17, #2f, #01, #03, #05, #21, #05, #23, #05, #27, #04, #24
    db #04, #26, #23, #01, #1c, #0e, #22, #18, #2d, #2c, #22, #1d, #c1, #74, #02, #24
    db #01, #01, #01, #28, #0c, #dd, #dd, #dd, #c1, #72, #02, #20, #01, #01, #01, #29
    db #0c, #ff, #ff, #ff, #c1, #74, #02, #1d, #01, #01, #01, #2a, #0c, #ff, #ff, #ff
    db #c1, #78, #02, #1d, #01, #01, #01, #2b, #0c, #ff, #ff, #ff, #01, #79, #20, #16
    db #04, #02, #08, #2f, #0c, #55, #99, #aa, #03, #7a, #25, #28, #02, #04, #00, #31
    db #11, #ee, #d4, #20, #07, #c5, #31, #f0, #d8, #c3, #78, #02, #1f, #02, #00, #04
    db #34, #11, #ee, #d4, #20, #03, #c5, #34, #f0, #d8, #c3, #73, #02, #0c, #04, #06
    db #00, #2e, #0d, #11, #12, #18, #0a, #c0, #74, #02, #0d, #00, #00, #00, #38, #09
    db #03, #73, #02, #0c, #04, #06, #00, #39, #1e, #55, #e0, #18, #0e, #e2, #20, #ec
    db #e2, #1a, #dc, #0b, #c5, #39, #c4, #2e, #c8, #18, #0b, #c7, #18, #09, #01, #02
    db #02, #28, #7b, #3b, #04, #03, #0c, #00, #00, #22, #00

Le48c_area_24:  ; LIFT ENTRANCE 6
    db #00, #0b, #18, #ac, #00, #08, #07, #12
    db #c0, #80, #8d, #82, #83, #84, #85, #ff, #0c, #c9, #95, #99, #03
    db #40, #02, #5a, #00, #10, #08, #02, #14, #11, #0b, #01, #00, #12, #31, #db, #2c
    db #12, #16, #09, #c0, #40, #02, #5e, #00, #12, #00, #01, #09, #06, #73, #0d, #2b
    db #05, #02, #0a, #05, #14, #b5, #b6, #00, #00, #01, #05, #01, #c5, #05, #f0, #d6
    db #03, #1f, #1e, #1e, #06, #00, #06, #07, #0a, #11, #c0, #22, #0d, #20, #00, #0a
    db #00, #08, #09, #c3, #1e, #02, #40, #08, #10, #00, #09, #0d, #11, #12, #16, #38
    db #c0, #21, #02, #3f, #00, #24, #00, #0a, #09, #01, #1e, #02, #3f, #08, #10, #01
    db #0b, #21, #11, #11, #22, #de, #0e, #e2, #1c, #ec, #e2, #1a, #dc, #0b, #c5, #0b
    db #c4, #09, #c8, #16, #39, #c7, #16, #2e, #e3, #01, #06, #24, #08, #3e, #02, #02
    db #01, #0e, #14, #64, #60, #66, #01, #00, #01, #01, #85, #0e, #b0, #da, #02, #00
    db #00, #00, #00, #00, #00, #7d, #09, #00

Le539_area_21:  ; RAVINE
    db #00, #27, #15, #e7, #01, #01, #46, #0f
    db #c0, #00, #00, #82, #00, #00, #00, #ff, #09, #01, #09, #02, #02, #02, #3b, #7b
    db #02, #0c, #03, #00, #00, #03, #02, #34, #44, #00, #02, #01, #03, #0d, #11, #12
    db #25, #0f, #c3, #02, #2e, #34, #00, #02, #01, #04, #0d, #11, #12, #25, #08, #03
    db #02, #28, #04, #00, #02, #01, #05, #0d, #11, #12, #1f, #db, #03, #02, #22, #13
    db #00, #02, #01, #06, #0d, #11, #12, #1b, #db, #01, #00, #00, #00, #09, #02, #7f
    db #0b, #0c, #00, #10, #00, #03, #09, #22, #04, #00, #02, #01, #0c, #0d, #11, #12
    db #1c, #d7, #01, #05, #21, #04, #01, #01, #10, #0d, #0c, #22, #44, #22, #01, #02
    db #21, #13, #03, #01, #01, #0e, #0c, #22, #44, #22, #01, #06, #21, #04, #03, #01
    db #01, #0f, #0c, #22, #44, #22, #01, #02, #27, #02, #02, #01, #24, #10, #0c, #22
    db #44, #22, #03, #02, #28, #24, #00, #02, #01, #11, #0d, #11, #12, #1e, #db, #01
    db #02, #02, #48, #07, #3b, #02, #12, #0c, #00, #00, #05, #01, #02, #02, #00, #07
    db #3d, #02, #13, #0c, #00, #00, #50, #01, #02, #3d, #02, #07, #02, #7b, #14, #0c
    db #00, #0f, #00, #03, #09, #2e, #34, #00, #02, #01, #15, #0d, #11, #12, #28, #01
    db #01, #02, #2d, #34, #07, #01, #01, #16, #0c, #22, #44, #22, #03, #09, #34, #44
    db #00, #02, #01, #17, #0d, #11, #12, #2e, #e1, #01, #02, #2b, #41, #07, #09, #07
    db #18, #0c, #55, #44, #ee, #c0, #08, #22, #04, #00, #36, #00, #1a, #09, #c0, #02
    db #22, #13, #00, #12, #00, #1b, #09, #01, #07, #27, #02, #02, #01, #24, #1c, #0c
    db #22, #44, #22, #03, #09, #28, #03, #00, #02, #01, #1d, #0d, #11, #12, #21, #d7
    db #c0, #08, #28, #03, #00, #36, #00, #1e, #09, #c0, #02, #28, #04, #00, #12, #00
    db #1f, #09, #c0, #02, #28, #24, #00, #12, #00, #20, #09, #c0, #08, #2e, #34, #00
    db #36, #00, #21, #09, #c0, #02, #2e, #34, #00, #12, #00, #22, #09, #c0, #08, #34
    db #44, #00, #36, #00, #23, #09, #c0, #02, #34, #44, #00, #12, #00, #24, #09, #03
    db #02, #2e, #04, #00, #02, #01, #25, #0d, #11, #12, #2a, #db, #03, #09, #2e, #04
    db #00, #02, #01, #26, #0d, #11, #12, #28, #08, #01, #02, #2d, #04, #07, #01, #01
    db #27, #0c, #22, #44, #22, #c0, #08, #2e, #04, #00, #36, #00, #28, #09, #c0, #02
    db #2e, #04, #00, #12, #00, #29, #09, #c1, #03, #28, #1c, #05, #01, #03, #2a, #0c
    db #22, #99, #aa, #01, #07, #28, #1c, #01, #05, #03, #2b, #1e, #99, #22, #22, #dc
    db #0e, #db, #19, #c5, #2b, #c4, #2a, #e3, #01, #dc, #08, #e2, #18, #c1, #f8, #24
    db #01, #03, #02, #2e, #34, #00, #02, #01, #2c, #1e, #dd, #e0, #25, #14, #e2, #20
    db #ec, #e2, #1a, #dc, #0b, #c5, #2c, #c4, #04, #c8, #25, #15, #c7, #25, #09, #00

Le721_area_17:  ; BELENUS KEY
    db #00, #0d, #11, #d0, #00, #05, #46, #0c
    db #c0, #80, #81, #82, #85, #00, #00, #ff
    db #09, #01, #20, #02, #02, #02, #3b, #7b, #02, #0c, #03, #00, #00, #03, #02, #02
    db #77, #00, #0a, #05, #03, #0d, #11, #12, #0f, #db, #01, #02, #02, #41, #1e, #3b
    db #02, #04, #0c, #00, #00, #20, #c0, #1f, #02, #79, #00, #36, #00, #05, #09, #c3
    db #20, #02, #77, #00, #0a, #05, #06, #0d, #11, #12, #13, #e1, #07, #02, #20, #43
    db #0f, #1d, #3a, #01, #10, #00, #70, #00, #00, #00, #00, #3a, #07, #11, #20, #43
    db #0f, #1d, #3a, #07, #10, #d0, #00, #00, #0f, #00, #0f, #3a, #cd, #09, #02, #7d
    db #10, #2c, #00, #09, #1c, #11, #09, #1f, #7d, #11, #2e, #7d, #19, #1f, #7d, #19
    db #02, #7d, #09, #02, #7d, #12, #01, #12, #0b, #09, #1f, #7d, #10, #0f, #00, #0a
    db #13, #11, #09, #1f, #7d, #11, #2e, #7d, #19, #1f, #7d, #03, #09, #02, #7d, #10
    db #1d, #00, #0b, #0a, #dd, #c0, #10, #02, #7c, #00, #24, #00, #0c, #09, #01, #1f
    db #02, #77, #01, #0a, #05, #0d, #22, #ff, #11, #11, #ce, #14, #00, #e2, #15, #db
    db #25, #e2, #37, #db, #25, #e2, #13, #ec, #e2, #1a, #dc, #0b, #c5, #0d, #c4, #06
    db #01, #20, #0e, #01, #01, #0e, #02, #01, #0e, #03, #01, #0e, #04, #01, #0e, #05
    db #01, #0e, #06, #01, #0e, #07, #01, #0e, #08, #01, #0e, #09, #01, #0e, #0a, #01
    db #0c, #14

Le813_area_19:  ; SPIRIT'S ABODE
    db #00, #08, #13, #58, #00, #10, #42, #0e
    db #c0, #80, #81, #82, #83, #84
    db #85, #ff, #09, #03, #02, #02, #38, #00, #20, #10, #01, #0d, #11, #12, #11, #05
    db #03, #34, #12, #7d, #0c, #22, #00, #02, #0d, #11, #12, #01, #06, #02, #00, #00
    db #00, #00, #00, #00, #7c, #09, #02, #00, #00, #00, #00, #00, #00, #7d, #09, #02
    db #00, #00, #00, #00, #00, #00, #7e, #09, #02, #00, #00, #00, #00, #00, #00, #7f
    db #09, #02, #00, #00, #00, #00, #00, #00, #7b, #09, #00

Le86c_area_27:  ; TUNNEL
    db #00, #04, #1b, #36, #00, #08, #45, #13
    db #c0, #80, #e6, #82, #83, #e9, #ea, #ff, #0b, #9a, #9b, #03, #02
    db #02, #3b, #00, #10, #08, #03, #0d, #11, #12, #0a, #ca, #03, #7d, #02, #3b, #00
    db #10, #08, #02, #0d, #11, #12, #15, #1b, #02, #00, #00, #00, #00, #00, #00, #7b
    db #09, #00

Le8a3_area_28:  ; THE TUBE
    db #00, #08, #1c, #5f, #00, #08, #47, #15
    db #c0, #80, #8d, #82, #86, #84
    db #85, #ff, #09, #03, #02, #02, #73, #00, #10, #08, #02, #0d, #11, #12, #15, #1a
    db #03, #1f, #02, #02, #08, #10, #00, #04, #0d, #11, #12, #1d, #eb, #c0, #23, #02
    db #02, #00, #00, #00, #03, #09, #02, #00, #00, #00, #00, #00, #00, #7c, #09, #01
    db #02, #02, #39, #42, #08, #01, #01, #0c, #00, #dd, #ff, #01, #02, #02, #4e, #42
    db #08, #01, #05, #0c, #00, #dd, #ff, #03, #02, #0a, #39, #40, #00, #16, #06, #0a
    db #d9, #00

Le903_area_29:  ; LIFT ENTRANCE 5
    db #00, #05, #1d, #4f, #00, #08, #07, #16
    db #c0, #80, #82, #83, #84, #85
    db #8d, #ff, #0d, #c9, #eb, #95, #99, #03, #5a, #02, #7d, #08, #10, #00, #02, #0d
    db #11, #12, #1c, #03, #03, #40, #02, #5c, #00, #10, #08, #01, #14, #11, #0b, #01
    db #01, #12, #31, #db, #2c, #12, #16, #0a, #03, #1f, #02, #1e, #06, #00, #06, #03
    db #10, #11, #12, #18, #08, #1a, #22, #18, #02, #00, #00, #00, #00, #00, #00, #7d
    db #09, #00

Le953_area_49:  ; LIFT
    db #00, #13, #31, #c4, #01, #18, #47, #25
    db #c0, #80, #81, #00, #83, #00
    db #00, #ff, #09, #03, #7d, #02, #33, #00, #30, #18, #02, #68, #11, #12, #16, #e1
    db #05, #08, #05, #0e, #05, #0f, #05, #10, #05, #11, #05, #12, #05, #13, #05, #14
    db #05, #17, #05, #19, #05, #1a, #05, #1b, #05, #1c, #05, #1d, #05, #1e, #05, #1f
    db #0b, #01, #00, #04, #14, #04, #17, #04, #1f, #04, #08, #12, #18, #e5, #2d, #0b
    db #01, #01, #04, #13, #04, #1a, #04, #1e, #04, #0e, #12, #1d, #e5, #2d, #0b, #01
    db #02, #04, #12, #04, #1b, #04, #1d, #04, #0f, #12, #21, #df, #2d, #0b, #01, #03
    db #04, #11, #04, #1c, #04, #19, #04, #10, #12, #29, #e5, #01, #40, #02, #1e, #02
    db #3b, #3e, #03, #0c, #30, #00, #00, #01, #42, #02, #1e, #3b, #3b, #02, #04, #0c
    db #00, #00, #50, #01, #42, #02, #5c, #3b, #3b, #02, #05, #0c, #00, #00, #05, #01
    db #74, #17, #20, #06, #12, #01, #06, #0c, #ee, #88, #77, #01, #76, #25, #21, #02
    db #02, #01, #07, #35, #22, #22, #11, #e0, #16, #24, #c8, #16, #24, #c8, #16, #26
    db #c7, #16, #29, #c7, #16, #2a, #c7, #16, #2b, #c7, #16, #34, #ed, #c5, #07, #c5
    db #0c, #c5, #0d, #c5, #0e, #c4, #0b, #c4, #08, #c4, #09, #c4, #0a, #d4, #01, #03
    db #01, #76, #21, #21, #02, #02, #01, #08, #1f, #22, #22, #11, #c5, #0b, #c5, #08
    db #c5, #0d, #c5, #0e, #c4, #07, #c4, #0c, #c4, #09, #c4, #0a, #d4, #01, #02, #01
    db #76, #1d, #21, #02, #02, #01, #09, #1f, #22, #22, #11, #c5, #0b, #c5, #0c, #c5
    db #09, #c5, #0e, #c4, #07, #c4, #08, #c4, #0d, #c4, #0a, #d4, #01, #01, #c1, #76
    db #19, #21, #02, #02, #01, #0a, #1f, #22, #22, #11, #c5, #0b, #c5, #0c, #c5, #0d
    db #c5, #0a, #c4, #07, #c4, #08, #c4, #09, #c4, #0e, #d4, #01, #00, #c1, #76, #25
    db #21, #02, #02, #01, #0b, #0e, #11, #11, #22, #f0, #07, #c1, #76, #21, #21, #02
    db #02, #01, #0c, #0e, #11, #11, #22, #f0, #08, #c1, #76, #1d, #21, #02, #02, #01
    db #0d, #0e, #11, #11, #22, #f0, #09, #01, #76, #19, #21, #02, #02, #01, #0e, #0e
    db #11, #11, #22, #f0, #0a, #c0, #66, #02, #3a, #06, #1e, #00, #01, #09, #c1, #6a
    db #27, #23, #04, #03, #04, #13, #0f, #dd, #dd, #dd, #92, #16, #01, #01, #46, #1d
    db #56, #10, #18, #06, #14, #0e, #ee, #88, #77, #e2, #16, #03, #48, #1f, #56, #0c
    db #14, #00, #15, #16, #aa, #e2, #16, #a2, #1e, #85, #15, #84, #0f, #81, #f8, #24
    db #01, #c3, #48, #1f, #56, #0c, #14, #00, #0f, #15, #11, #ce, #05, #00, #d4, #20
    db #05, #f0, #d8, #ec, #e2, #08, #00

Leb18_area_30:  ; TUNNEL
    db #00, #05, #1e, #5c, #00, #08, #45, #13
    db #c0
    db #80, #82, #83, #e6, #e9, #ea, #ff, #0b, #9a, #9b, #c3, #02, #02, #3b, #00, #10
    db #08, #02, #0d, #11, #12, #0b, #ca, #03, #7d, #02, #3b, #00, #10, #08, #01, #0d
    db #11, #12, #15, #20, #03, #02, #02, #3b, #00, #10, #08, #03, #26, #77, #ce, #05
    db #00, #e2, #15, #db, #25, #e2, #31, #db, #25, #e2, #13, #ec, #e2, #1a, #dc, #0b
    db #c5, #03, #c4, #02, #c8, #0b, #01, #c7, #0b, #04, #02, #00, #00, #00, #00, #00
    db #00, #7b, #09, #00

Leb75_area_31:  ; TUNNEL
    db #00, #05, #1f, #54, #00, #08, #45, #13
    db #c0, #80, #82, #83
    db #e6, #e9, #ea, #ff, #0b, #9a, #9b, #03, #7d, #02, #3b, #00, #10, #08, #02, #0d
    db #11, #12, #15, #1f, #c3, #02, #02, #3b, #00, #10, #08, #03, #0d, #11, #12, #20
    db #db, #03, #02, #02, #3b, #00, #10, #08, #01, #1e, #ff, #e0, #20, #06, #e2, #1c
    db #ec, #dc, #0b, #c4, #03, #c8, #20, #01, #c7, #20, #02, #c5, #01, #e3, #01, #02
    db #00, #00, #00, #00, #00, #00, #7b, #09, #00

Lebca_area_32:  ; EPONA
    db #00, #08, #20, #9d, #00, #10, #07, #17
    db #c0, #80, #81, #82, #83, #84, #85, #ff, #0a, #8b, #c3, #7d, #02, #38, #00
    db #20, #10, #02, #0d, #11, #12, #1f, #e1, #03, #38, #02, #02, #10, #20, #00, #03
    db #0d, #11, #12, #08, #13, #01, #7c, #02, #38, #01, #20, #10, #01, #21, #22, #11
    db #11, #de, #06, #e2, #1c, #ec, #e2, #1a, #dc, #0b, #c5, #01, #c4, #02, #c8, #1f
    db #01, #c7, #1f, #03, #e3, #01, #06, #7b, #0f, #38, #01, #03, #04, #06, #14, #46
    db #46, #64, #00, #02, #01, #02, #85, #06, #b0, #da, #06, #73, #02, #6f, #05, #02
    db #09, #07, #14, #a5, #a2, #00, #00, #01, #05, #01, #c5, #07, #f0, #d6, #07, #3c
    db #12, #3c, #08, #08, #08, #09, #12, #9a, #9a, #00, #04, #04, #04, #04, #f0, #0a
    db #06, #3c, #1a, #3c, #08, #02, #08, #0a, #16, #a9, #a9, #70, #02, #02, #06, #06
    db #c5, #09, #c5, #0a, #f0, #d9, #00

Lec68_area_33:  ; LIFT ENTRANCE 4
    db #00, #06, #21, #67, #00, #08, #46, #19
    db #c0
    db #80, #8d, #82, #86, #84, #85, #ff, #0d, #ec, #8e, #a5, #a6, #03, #02, #02, #73
    db #00, #10, #08, #02, #0d, #11, #12, #15, #1e, #02, #00, #00, #00, #00, #00, #00
    db #7c, #09, #07, #1f, #0a, #1f, #04, #04, #04, #04, #12, #6d, #6d, #00, #02, #02
    db #02, #02, #f0, #05, #06, #1f, #0e, #1f, #04, #01, #04, #05, #16, #d6, #d6, #70
    db #01, #01, #03, #03, #c5, #04, #c5, #05, #f0, #d9, #03, #02, #02, #04, #00, #10
    db #08, #01, #14, #11, #0b, #01, #02, #12, #31, #db, #2c, #12, #16, #0b, #00

Lecd0_area_35:  ; NANTOSUELTA
    db #00, #08, #23, #98, #00, #10, #07, #1a
    db #c0, #80, #81, #82, #83, #84, #85, #ff, #0b
    db #8b, #a1, #c3, #02, #02, #38, #00, #20, #10, #02, #0d, #11, #12, #0c, #ca, #03
    db #7d, #02, #38, #00, #20, #10, #03, #0d, #11, #12, #25, #01, #03, #02, #02, #38
    db #00, #20, #10, #01, #26, #aa, #ce, #04, #00, #e2, #15, #db, #25, #e2, #31, #db
    db #25, #e2, #13, #ec, #e2, #1a, #dc, #0b, #c5, #01, #c4, #02, #c8, #0c, #08, #c7
    db #0c, #04, #02, #00, #00, #00, #00, #00, #00, #7f, #09, #06, #07, #02, #07, #05
    db #02, #09, #05, #14, #a5, #a2, #00, #00, #01, #05, #01, #c5, #05, #f0, #d6, #07
    db #3c, #12, #3c, #08, #08, #08, #07, #12, #8a, #8a, #00, #04, #04, #04, #04, #f0
    db #08, #06, #3c, #1a, #3c, #08, #02, #08, #08, #16, #a8, #a8, #d0, #02, #02, #06
    db #06, #c5, #07, #c5, #08, #f0, #d9, #00

Led69_area_37:  ; NO ROOM
    db #00, #16, #25, #58, #01, #08, #46, #1c
    db #c0, #80, #81, #82, #00, #84, #85, #ff, #09, #03, #02, #02, #1c, #00, #10, #08
    db #02, #0d, #11, #12, #23, #db, #c0, #02, #02, #20, #00, #12, #00, #01, #09, #01
    db #16, #02, #02, #02, #3b, #7b, #03, #0c, #03, #00, #00, #c3, #02, #02, #5c, #00
    db #12, #08, #04, #0d, #11, #12, #24, #db, #c0, #02, #02, #60, #00, #12, #00, #05
    db #09, #c0, #15, #02, #60, #00, #36, #00, #06, #09, #c3, #16, #02, #5c, #00, #12
    db #08, #07, #0d, #11, #12, #26, #e1, #c0, #15, #02, #20, #00, #36, #00, #08, #09
    db #c3, #16, #02, #1c, #00, #10, #08, #09, #0d, #11, #12, #15, #22, #03, #02, #1c
    db #5c, #00, #10, #08, #0a, #0d, #11, #12, #2c, #db, #03, #16, #1c, #5c, #00, #10
    db #08, #0b, #0d, #11, #12, #15, #24, #01, #02, #1b, #5c, #04, #01, #08, #0c, #0c
    db #44, #55, #dd, #01, #12, #1b, #5c, #04, #01, #08, #0d, #0c, #44, #55, #dd, #c0
    db #02, #1c, #60, #00, #12, #00, #0e, #09, #c0, #15, #1c, #60, #00, #36, #00, #0f
    db #09, #01, #02, #02, #5b, #01, #12, #0a, #10, #18, #dd, #55, #55, #e2, #1a, #dc
    db #0b, #c5, #10, #c4, #11, #c4, #04, #e3, #01, #c1, #02, #02, #5b, #0a, #12, #01
    db #11, #18, #55, #55, #dd, #e2, #1b, #dc, #0b, #c5, #11, #c5, #04, #c4, #10, #e3
    db #01, #01, #15, #02, #5b, #01, #12, #0a, #12, #24, #88, #55, #55, #ce, #09, #00
    db #e2, #15, #db, #19, #e2, #46, #db, #19, #e2, #13, #ec, #e2, #1a, #dc, #0b, #c5
    db #12, #c4, #07, #c4, #13, #c1, #0c, #02, #5b, #0a, #12, #01, #13, #18, #55, #55
    db #88, #e2, #1b, #dc, #0b, #c5, #13, #c5, #07, #c4, #12, #e3, #01, #06, #14, #0a
    db #1c, #01, #02, #02, #14, #14, #69, #ad, #99, #00, #01, #01, #01, #85, #14, #b0
    db #da, #01, #15, #02, #1c, #01, #10, #08, #15, #1f, #22, #11, #11, #de, #14, #e2
    db #1c, #ec, #e2, #1a, #dc, #0b, #c5, #15, #c4, #09, #c8, #15, #2c, #c7, #15, #04
    db #00

Leec2_area_36:  ; STALACTITES
    db #00, #07, #24, #87, #00, #10, #07, #1b
    db #c0, #80, #81, #82, #83, #84, #85
    db #ff, #0d, #9c, #9d, #9e, #a1, #03, #7d, #02, #38, #00, #20, #10, #02, #0d, #11
    db #12, #25, #05, #02, #00, #00, #00, #00, #00, #00, #7f, #09, #01, #3a, #30, #3d
    db #0c, #0d, #0c, #03, #24, #dd, #aa, #ff, #e2, #18, #e0, #2c, #0a, #db, #19, #e2
    db #08, #ec, #dc, #0e, #c5, #03, #c4, #05, #c8, #2c, #08, #c7, #2c, #01, #e3, #01
    db #01, #3a, #23, #49, #0c, #1a, #0c, #04, #24, #99, #66, #55, #e2, #18, #e0, #2c
    db #0a, #db, #19, #e2, #08, #ec, #dc, #0e, #c5, #04, #c4, #06, #c8, #2c, #09, #c7
    db #2c, #05, #e3, #01, #c3, #3a, #3d, #3d, #0c, #00, #0c, #05, #0a, #aa, #c3, #3a
    db #3d, #49, #0c, #00, #0c, #06, #0a, #66, #00

Lef4a_area_38:  ; THE TRAPEZE
    db #00, #11, #26, #ea, #00, #10, #07, #1d
    db #c0, #80, #81, #82, #83, #84, #85, #ff, #0c, #9c, #9d, #9e, #03, #02, #02
    db #3a, #00, #20, #10, #02, #0d, #11, #12, #25, #06, #02, #00, #00, #00, #00, #00
    db #00, #7d, #09, #01, #02, #02, #38, #45, #1c, #01, #01, #0c, #55, #ee, #77, #01
    db #46, #02, #39, #01, #16, #44, #03, #0c, #55, #88, #00, #01, #3a, #02, #6d, #0c
    db #06, #10, #04, #0c, #05, #77, #ee, #01, #47, #26, #38, #2e, #01, #02, #08, #0c
    db #11, #99, #88, #01, #75, #32, #33, #08, #01, #0b, #09, #0c, #55, #88, #77, #0a
    db #48, #27, #39, #00, #16, #00, #0a, #10, #11, #48, #27, #39, #48, #3d, #39, #0a
    db #74, #27, #39, #00, #16, #00, #0b, #10, #11, #74, #27, #39, #74, #3d, #39, #01
    db #41, #27, #3d, #0c, #02, #02, #0c, #0c, #11, #99, #88, #0a, #42, #29, #3e, #00
    db #14, #00, #0d, #10, #11, #42, #29, #3e, #42, #3d, #3e, #0a, #4c, #29, #3e, #00
    db #14, #00, #0e, #10, #11, #4c, #29, #3e, #4c, #3d, #3e, #01, #75, #33, #33, #01
    db #03, #0b, #0f, #0c, #ff, #99, #55, #01, #76, #33, #33, #07, #03, #01, #10, #0c
    db #00, #99, #55, #01, #76, #33, #3d, #07, #03, #01, #11, #0c, #00, #99, #55, #06
    db #78, #33, #34, #05, #02, #09, #13, #14, #25, #c2, #00, #00, #01, #05, #01, #c5
    db #13, #f0, #d6, #00

Lf035_area_40:  ; TUNNEL
    db #00, #0a, #28, #77, #00, #04, #45, #13
    db #c0, #80, #84, #85
    db #00, #00, #00, #ff, #09, #03, #3d, #02, #02, #04, #08, #00, #02, #0d, #11, #12
    db #29, #01, #01, #43, #02, #02, #02, #0b, #7b, #03, #0c, #03, #00, #00, #01, #39
    db #02, #02, #02, #0b, #7b, #04, #0c, #30, #00, #00, #01, #3b, #0d, #02, #08, #02
    db #7b, #05, #0c, #00, #04, #00, #03, #3b, #02, #77, #00, #08, #04, #06, #0d, #11
    db #12, #15, #21, #c0, #3c, #02, #79, #00, #12, #00, #01, #09, #03, #3b, #02, #1e
    db #00, #08, #04, #07, #0d, #11, #12, #15, #28, #c0, #3c, #02, #1f, #00, #12, #00
    db #08, #09, #02, #00, #00, #00, #00, #00, #00, #7e, #09, #00

Lf0ad_area_41:  ; LIFT ENTRANCE 3
    db #00, #05, #29, #47, #00, #08, #46, #1f
    db #c0, #80, #82, #83, #84, #85, #8d, #ff, #0c, #c9, #95, #99
    db #03, #42, #02, #7d, #08, #10, #00, #02, #0d, #11, #12, #28, #de, #c0, #46, #02
    db #7c, #00, #24, #00, #01, #09, #03, #40, #02, #5a, #00, #10, #08, #03, #14, #11
    db #0b, #01, #03, #12, #31, #db, #2c, #12, #16, #0c, #02, #00, #00, #00, #00, #00
    db #00, #7d, #09, #00

Lf0f5_area_42:  ; TUNNEL
    db #00, #04, #2a, #36, #00, #08, #45, #13
    db #c0, #80, #82, #83
    db #e6, #e9, #ea, #ff, #0b, #9a, #9b, #03, #7d, #02, #3b, #00, #10, #08, #02, #0d
    db #11, #12, #15, #29, #03, #02, #02, #3b, #00, #10, #08, #03, #0d, #11, #12, #2b
    db #db, #02, #00, #00, #00, #00, #00, #00, #7b, #09, #00

Lf12c_area_43:  ; THE SWITCH
    db #00, #0b, #2b, #c7, #00, #10, #07, #20
    db #c0, #80, #81, #82, #83, #84, #85, #ff, #0e, #9f, #a0, #a1, #a3
    db #a4, #03, #7d, #02, #38, #00, #20, #10, #02, #0d, #11, #12, #2a, #e1, #c3, #38
    db #02, #02, #10, #20, #00, #03, #0d, #11, #12, #08, #14, #01, #3d, #16, #7a, #06
    db #0e, #03, #01, #0c, #11, #11, #55, #03, #3f, #1a, #7a, #02, #06, #00, #04, #0a
    db #11, #07, #3f, #1c, #76, #02, #04, #04, #05, #20, #4a, #4a, #00, #00, #04, #02
    db #04, #db, #08, #dc, #0e, #c5, #05, #c5, #06, #c4, #07, #c4, #08, #c4, #03, #e3
    db #01, #06, #3f, #20, #76, #02, #02, #04, #06, #12, #46, #4a, #00, #00, #02, #02
    db #02, #f0, #05, #c6, #3f, #1a, #76, #02, #04, #04, #07, #12, #4a, #4a, #00, #00
    db #04, #02, #04, #f0, #08, #c7, #3f, #18, #76, #02, #02, #04, #08, #20, #46, #4a
    db #00, #00, #02, #02, #02, #db, #08, #dc, #0e, #c5, #07, #c5, #08, #c4, #05, #c4
    db #06, #c5, #03, #e3, #01, #02, #00, #00, #00, #00, #00, #00, #7f, #09, #06, #73
    db #02, #6f, #05, #02, #09, #09, #14, #a5, #a2, #00, #00, #01, #05, #01, #c5, #09
    db #f0, #d6, #01, #0e, #5e, #03, #5c, #0e, #45, #03, #45, #07, #45, #08, #44, #05
    db #44, #06

Lf203_area_44:  ; THE PILLAR
    db #00, #0e, #2c, #c0, #00, #10, #07, #21
    db #c0, #80, #81, #82, #83, #84
    db #85, #ff, #0a, #8f, #03, #02, #02, #38, #00, #20, #10, #02, #0d, #11, #12, #0d
    db #ca, #03, #7d, #02, #38, #00, #20, #10, #03, #0d, #11, #12, #25, #0e, #c1, #3a
    db #02, #3d, #0c, #0d, #0c, #01, #0c, #dd, #aa, #ff, #c1, #3a, #02, #49, #0c, #1a
    db #0c, #05, #0c, #99, #66, #55, #01, #3a, #02, #55, #0c, #2e, #0c, #06, #0c, #dd
    db #aa, #ff, #03, #3a, #02, #3d, #0c, #00, #0c, #08, #0a, #aa, #03, #3a, #02, #49
    db #0c, #00, #0c, #09, #0a, #66, #01, #3c, #02, #3f, #08, #04, #14, #0a, #14, #22
    db #ee, #55, #dc, #0e, #c5, #0a, #c4, #0b, #e3, #01, #c1, #48, #02, #3f, #08, #04
    db #14, #0b, #0c, #22, #ee, #55, #03, #3b, #30, #5b, #04, #00, #04, #07, #0e, #20
    db #c5, #07, #f0, #d9, #02, #00, #00, #00, #00, #00, #00, #7f, #09, #06, #07, #02
    db #07, #05, #02, #09, #0c, #14, #a5, #a2, #00, #00, #01, #05, #01, #c5, #0c, #f0
    db #d6, #03, #60, #32, #52, #03, #00, #06, #0d, #11, #b0, #d4, #20, #0a, #c5, #0d
    db #f0, #d8, #00

Lf2c4_area_46:  ; THE RAT TRAP
    db #00, #0d, #2e, #b7, #00, #10, #07, #23
    db #c0, #80, #81, #82, #83, #84, #85, #ff, #09
    db #03, #02, #02, #38, #00, #20, #10, #02, #0d, #11, #12, #15, #23
    db #03, #7b, #11, #3d, #00, #0c, #06, #01, #24, #22, #d4, #20, #06, #c5, #01, #dc, #0a, #e2, #11, #c1, #c0, #d4, #01, #da, #db, #10, #c5, #07, #c5, #0e, #c4, #0b, #e3, #01, #dc, #0e
    db #01, #7b, #0d, #3a, #02, #13, #0c, #06, #0c, #ff, #66, #bb
    db #02, #00, #00, #00, #00, #00, #00, #7f, #09
    db #01, #63, #26, #02, #01, #17, #7b, #07, #0c, #99, #88, #77
    db #01, #02, #02, #6b, #7b, #24, #01, #08, #0c, #00, #88, #ee
    db #01, #02, #02, #14, #7b, #24, #01, #09, #0c, #00, #88, #ee
    db #01, #02, #26, #14, #0a, #01, #58, #0a, #0c, #77, #88, #99
    db #c1, #63, #09, #15, #01, #17, #56, #0b, #0c, #99, #88, #77
    db #03, #63, #09, #6b, #01, #1d, #00, #0c, #0a, #11
    db #03, #63, #09, #15, #01, #1d, #00, #0d, #0a, #11
    db #0a, #63, #20, #40, #1a, #06, #00, #0e, #10, #11, #7d, #20, #40, #63, #26, #40
    db #00


; --------------------------------
; RAM Variables:

Lfdfd_interrupt_jp: equ #fdfd  ; 1 byte
Lfdfe_interrupt_pointer: equ #fdfe  ; 2 bytes
Lfe00_interrupt_vector_table: equ #fe00  ; 257 bytes
