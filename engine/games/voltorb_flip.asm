; wram usage
; 25 bytes for board
; 1 byte for cursor position
; 1 byte to count number of cards turned
; 1 byte for level 8 combo counter
; 1 byte for current level
; 2 bytes for payout
; 20 bytes for board stats

; jumptable constants
	const_def
	const VFLIP_ASK_PLAY
	const VFLIP_INIT
	const VFLIP_CHOOSE_CARD
	const VFLIP_FLIP_CARD
	const VFLIP_FINISH_WIN
	const VFLIP_GIVE_PAYOUT
	const VFLIP_FINISH_LOSE
	const VFLIP_FINISH_UP
	const VFLIP_QUIT
VFLIP_END_LOOP_F EQU 7

VFLIP_NUMTILE_1 EQU $0c
VFLIP_NUMTILE_2 EQU $0d
VFLIP_NUMTILE_3 EQU $0e

VFLIP_RIGHT_NOTE EQU 2
VFLIP_LEFT_NOTE  EQU 3
VFLIP_UP_NOTE    EQU 4
VFLIP_DOWN_NOTE  EQU 5

_VoltorbFlip::
	ld hl, wOptions
	set NO_TEXT_SCROLL, [hl]
	ldh a, [hBGMapMode]
	call .InitGFX
	call DelayFrame
.loop
	call VoltorbFlipLoop
	jr nc, .loop
	call WaitSFX
	call ClearBGPalettes
	ld hl, wOptions
	res NO_TEXT_SCROLL, [hl]
	ld hl, rLCDC
	res rLCDC_SPRITE_SIZE, [hl]
	ret

.InitGFX:
	call ClearBGPalettes
	call ClearTilemap
	call ClearSprites
	ld de, MUSIC_NONE
	call PlayMusic
	call DelayFrame
	call DisableLCD
	hlbgcoord 0, 0
	ld bc, vBGMap1 - vBGMap0
	ld a, " "
	call ByteFill
	ld b, SCGB_VOLTORB_FLIP
	call GetSGBLayout
	callfar ClearSpriteAnims

	; clear minigame-related ram
	ld hl, wVoltorbFlip
	ld bc, wVoltorbFlipEnd - wVoltorbFlip
	xor a
	call ByteFill

	; load graphics
	ld hl, VoltorbFlipSpriteGFX
	ld de, vTiles0 tile $00
	call Decompress

	ld hl, VoltorbFlipTileGFX
	ld de, vTiles2 tile $00
	call Decompress

	; init tilemap and attrmap
	call VoltorbFlip_CopyTileAttrMapUpper
	call VoltorbFlip_CopyTileAttrMapLower

	; set sprite mode to 8x16
	ld hl, rLCDC
	set rLCDC_SPRITE_SIZE, [hl]
	call EnableLCD

	call VoltorbFlip_GetPals

	call WaitBGMap2

	ld de, MUSIC_GAME_CORNER
	call PlayMusic

	xor a
	ld [wJumptableIndex], a
	ld [wPayout], a
	ld [wPayout + 1], a

	ld a, 1
	ld [wVFlipLevel], a

	ret

VoltorbFlip_CopyTileAttrMapUpper:
	ld hl, VoltorbFlipTilemap
	decoord 0, 0
	ld bc, SCREEN_WIDTH * 12
	call CopyBytes

	ld hl, VoltorbFlipAttrmap
	decoord 0, 0, wAttrmap
	ld bc, SCREEN_WIDTH * 12
	call CopyBytes

	ret

VoltorbFlip_CopyTileAttrMapLower:
	ld hl, VoltorbFlipTilemap + SCREEN_WIDTH * 12
	decoord 0, 12
	ld bc, SCREEN_WIDTH * 6
	call CopyBytes

	ld hl, VoltorbFlipAttrmap + SCREEN_WIDTH * 12
	decoord 0, 12, wAttrmap
	ld bc, SCREEN_WIDTH * 6
	call CopyBytes

	ret

VoltorbFlip_GetPals:
	ld a, %11100100
	call DmgToCgbBGPals
	lb de, %11100100, %11100100
	call DmgToCgbObjPals
	ret

VFlip_CursorToBC:
	ld a, [wVFlipCursorPos]
	ld c, 5
	call SimpleDivide
	ld c, a
	ret

VFlip_BCToCursor:
	ld a, b
	add a
	add a
	add b
	add c
	ld [wVFlipCursorPos], a
	ret

VoltorbFlipLoop:
	ld a, [wJumptableIndex]
	bit VFLIP_END_LOOP_F, a
	jr nz, .stop
	call VFlipJumptable
	call DelayFrame
	and a
	ret

.stop
	scf
	ret

VFlip_DrawPayout:
	hlcoord 16, 17
	ld de, wPayout
	lb bc, PRINTNUM_LEADINGZEROS | 2, 4
	call PrintNum
	ret

VFlip_DrawLevel:
	hlcoord 18, 15
	ld a, [wVFlipLevel]
	add "0"
	ld [hl], a
	ret

VFlipJumptable:
	jumptable .Jumptable, wJumptableIndex

.Jumptable:
	dw VFlipAction_AskPlay        ; VFLIP_ASK_PLAY
	dw VFlipAction_Init           ; VFLIP_START_GAME
	dw VFlipAction_ChooseCard     ; VFLIP_CHOOSE_CARD
	dw VFlipAction_FlipCard       ; VFLIP_FLIP_CARD
	dw VFlipAction_FinishWin      ; VFLIP_FINISH_WIN
	dw VFlipAction_GivePayout     ; VFLIP_GIVE_PAYOUT
	dw VFlipAction_FinishLose     ; VFLIP_FINISH_LOSE
	dw VFlipAction_FinishAll      ; VFLIP_FINISH_UP
	dw VFlipAction_Quit           ; VFLIP_QUIT

VFlipAction_Next:
	ld hl, wJumptableIndex
	inc [hl]
	ret

VFlipAction_Quit:
	ld hl, wJumptableIndex
	set VFLIP_END_LOOP_F, [hl]
	ret

VFlipAction_Init:
	; init game variables
	xor a
	ld hl, wVFlipBoard
	ld bc, 25
	call ByteFill
	ld [wVFlipCursorPos], a
	ld [wVFlipCardsTurned], a

	; init board
	call VFlip_GenerateBoard
	call VFlip_CalcBoardStats

	call VFlip_DrawLevel
	call VFlip_DrawBoardStats

	call VFlipAction_Next
	ret

VFlipAction_AskPlay:
	call VFlip_AskPlay
	jr c, .exit_game
	call VFlipAction_Next
	call VoltorbFlip_CopyTileAttrMapUpper
	call VoltorbFlip_CopyTileAttrMapLower
	call WaitBGMap2
	ret

.exit_game
	ld a, VFLIP_QUIT
	ld [wJumptableIndex], a
	ret

VFlip_AskPlay:
	call VFlip_HideCursor
	ld hl, .VFlipPlayText
	call PrintText
	call LoadMenuTextbox
	call WaitBGMap2
	lb bc, 14, 12
	call PlaceYesNoBox
	ld a, [wMenuCursorY]
	dec a
	call CloseWindow
	and a
	jr nz, .exit
	and a
	ret

.exit
	scf
	ret

.VFlipPlayText
	text "Play Voltorb"
	line "Flip?"
	done

VFlipAction_ChooseCard:
	call JoyTextDelay
	ldh a, [hJoyLast]
	and A_BUTTON
	jr nz, .card_chosen
	ldh a, [hJoyLast]
	and START
	jr nz, .ask_quit
	call VFlip_HandleJoypad
	call VFlip_DrawCursor
	call VFlip_DrawPayout
	ret

.card_chosen
	ld a, VFLIP_FLIP_CARD
	ld [wJumptableIndex], a
	ret

.ask_quit
	ret

VFlip_HandleJoypad:
	; check if b is held
	; if yes, then switch to toggling notes
	ldh a, [hJoyDown]
	and B_BUTTON
	jr nz, VFlip_JoypadNoteMode
	; get cursor pos as x and y
	call VFlip_CursorToBC

	; try move cursor
	ld hl, hJoyLast
	ld a, [hl]
	and D_LEFT
	jr nz, .d_left
	ld a, [hl]
	and D_RIGHT
	jr nz, .d_right
	ld a, [hl]
	and D_UP
	jr nz, .d_up
	ld a, [hl]
	and D_DOWN
	jr nz, .d_down
	ret

.d_left
	dec c
	ld a, c
	cp -1
	jr nz, .finish
	ld c, 4
	jr .finish

.d_right
	inc c
	ld a, c
	cp 5
	jr nz, .finish
	ld c, 0
	jr .finish

.d_up
	dec b
	ld a, b
	cp -1
	jr nz, .finish
	ld b, 4
	jr .finish

.d_down
	inc b
	ld a, b
	cp 5
	jr nz, .finish
	ld b, 0
	; fallthrough
.finish
	call VFlip_BCToCursor
	ret

VFlip_JoypadNoteMode:
	ldh a, [hJoyLast]
	and D_PAD
	ret z
	ld a, [wVFlipCursorPos]
	ld c, a
	ld b, 0
	ld hl, wVFlipBoard
	add hl, bc
	ld a, [hl]
	and %10000000
	ret nz
	ldh a, [hJoyLast]
	bit D_RIGHT_F, a
	jr nz, .right
	bit D_LEFT_F, a
	jr nz, .left
	bit D_UP_F, a
	jr nz, .up
; fallthrough
.down
	ld a, 1 << VFLIP_DOWN_NOTE
	xor [hl]
	ld [hl], a
	bit VFLIP_DOWN_NOTE, [hl]
	push af
	hlcoord 1, 2
	jr .finish

.right
	ld a, 1 << VFLIP_RIGHT_NOTE
	xor [hl]
	ld [hl], a
	bit VFLIP_RIGHT_NOTE, [hl]
	push af
	hlcoord 2, 1
	jr .finish

.left
	ld a, 1 << VFLIP_LEFT_NOTE
	xor [hl]
	ld [hl], a
	bit VFLIP_LEFT_NOTE, [hl]
	push af
	hlcoord 0, 1
	jr .finish

.up
	ld a, 1 << VFLIP_UP_NOTE
	xor [hl]
	ld [hl], a
	bit VFLIP_UP_NOTE, [hl]
	push af
	hlcoord 1, 0
; fallthrough
.finish
	call VFlip_CursorToBC
	ld a, b
	ld b, 0
	add hl, bc
	add hl, bc
	add hl, bc
	ld bc, SCREEN_WIDTH * 3
	call AddNTimes
	pop af
	jr z, .was_set
	inc [hl]
	ret

.was_set
	dec [hl]
	ret

VFlipAction_FlipCard:
	call VFlip_TryFlipCard
	jr nc, .already_flipped

	ld de, SFX_EGG_CRACK
	call PlaySFX
	call WaitSFX

	call VFlip_CardFlipAnimation

	ld hl, wVFlipCardsTurned
	inc [hl]
	and a
	jr z, .lose_game

	call VFlip_UpdatePayout

	call VFlip_CheckIfBoardComplete
	jr c, .win_game

.already_flipped
	ld a, VFLIP_CHOOSE_CARD
	ld [wJumptableIndex], a
	ret

.win_game
	ld a, VFLIP_FINISH_WIN
	ld [wJumptableIndex], a
	ret

.lose_game
	ld a, VFLIP_FINISH_LOSE
	ld [wJumptableIndex], a
	ret

VFlip_UpdatePayout:
	ld c, a
	ld hl, wPayout
	ldi a, [hl]
	or [hl]
	jr z, .payout_at_zero
	ld a, c
	cp 1
	ret z ; payout non-zero, card is one, no change

	ld a, [wPayout]
	ld h, a
	ld a, [wPayout + 1]
	ld l, a
	ld a, c
	ld b, h
	ld c, l
	add hl, hl
	cp 3
	jr nz, .done
	add hl, bc
.done
	ld a, h
	ld [wPayout], a
	ld a, l
	ld [wPayout + 1], a
	ret

.payout_at_zero
	ld a, c
	ld [wPayout + 1], a
	ret

VFlip_CheckIfBoardComplete:
	push af
	ld hl, wVFlipBoard
	ld c, 25
.loop
	ldi a, [hl]
	bit 7, a
	jr nz, .cont
	and %00000011
	cp 2
	jr z, .not_complete
	cp 3
	jr z, .not_complete
.cont
	dec c
	jr nz, .loop
	pop af
	scf
	ret

.not_complete
	pop af
	and a
	ret

VFlip_TryFlipCard:
	ld a, [wVFlipCursorPos]
	ld c, a
	ld b, 0
	ld hl, wVFlipBoard
	add hl, bc
	and a
	bit 7, [hl]
	ret nz ; dont flip if already done
	ld b, [hl]
	set 7, [hl]
	push af
	push bc
	hlcoord 1, 1
	call VFlip_CursorToBC
	ld e, b
	ld b, 0
	add hl, bc
	add hl, bc
	add hl, bc
	ld bc, SCREEN_WIDTH * 3
	ld a, e
	call AddNTimes
	pop bc
	call .clear_notes
	pop af
	ld a, b
	and %00000011
	push af
	add VFLIP_NUMTILE_1 - 1
	ld [hl], a
	xor a
	ldh [hBGMapMode], a
	pop af
	scf
	ret

.clear_notes
	bit VFLIP_RIGHT_NOTE, b
	call nz, .right_note
	bit VFLIP_LEFT_NOTE, b
	call nz, .left_note
	bit VFLIP_UP_NOTE, b
	call nz, .up_note
	bit VFLIP_DOWN_NOTE, b
	call nz, .down_note
	ret

.right_note
	ld de, 1
	jr .finish_note

.left_note
	ld de, -1
	jr .finish_note

.up_note
	ld de, -SCREEN_WIDTH
	jr .finish_note

.down_note
	ld de, SCREEN_WIDTH
.finish_note
	push hl
	add hl, de
	dec [hl]
	pop hl
	ret
	

VFlip_GenerateBoard:
	; get card counts
	ld a, [wVFlipLevel]
	dec a
	ld c, a
	add a
	add a
	add a
	add a
	sub c
	ld d, a
	call Random
	ld c, 5
	call SimpleDivide
	ld c, a
	add a
	add c
	add d
	ld c, a
	ld b, 0
	ld hl, .layouts
	add hl, bc
	ld d, h
	ld e, l
	; init board
	ld hl, wVFlipBoard
	ld c, 25 ; board size
	; loop 2 cards
	ld a, 2
	call .write_card
	; loop 3 cards
	ld a, 3
	call .write_card
	; loop bombs
	xor a
	call .write_card
	; fill with 1 cards
	ld a, 1
.fill_board_loop
	ldi [hl], a
	dec c
	jr nz, .fill_board_loop

	; shuffle board
	ld c, 23 ; board size - 2
	ld hl, wVFlipBoard
.shuffle_loop
	call Random
	and %00011111
	cp 25
	jr nc, .shuffle_loop
	ld b, [hl]
	push hl
	ld h, HIGH(wVFlipBoard)
	add LOW(wVFlipBoard)
	jr nz, .no_overflow
	inc h
.no_overflow
	ld l, a
	ld a, [hl]
	ld [hl], b
	pop hl
	ldi [hl], a
	dec c
	jr nz, .shuffle_loop

	ret

.write_card
	push af
	ld a, [de]
	inc de
	and a
	jr z, .card_skip
	ld b, a
	pop af
.loop_card
	ldi [hl], a
	dec c
	dec b
	jr nz, .loop_card
	ret

.card_skip
	pop af
	ret

.layouts
	; level 1
	db 3, 1, 6
	db 0, 3, 6
	db 5, 0, 6
	db 2, 2, 6
	db 4, 1, 6
	; level 2
	db 1, 3, 7
	db 6, 0, 7
	db 3, 2, 7
	db 0, 4, 7
	db 5, 1, 7
	; level 3
	db 2, 3, 8
	db 7, 0, 8
	db 4, 2, 8
	db 1, 4, 8
	db 6, 1, 8
	; level 4
	db 3, 3, 8
	db 0, 5, 8
	db 8, 0, 10
	db 5, 2, 10
	db 2, 4, 10
	; level 5
	db 7, 1, 10
	db 4, 3, 10
	db 1, 5, 10
	db 9, 0, 10
	db 6, 2, 10
	; level 6
	db 3, 4, 10
	db 0, 6, 10
	db 8, 1, 10
	db 5, 3, 10
	db 2, 5, 10
	; level 7
	db 7, 2, 10
	db 4, 4, 10
	db 1, 6, 13
	db 9, 1, 13
	db 6, 3, 10
	; level 8
	db 0, 7, 10
	db 8, 2, 10
	db 5, 4, 10
	db 2, 6, 10
	db 7, 3, 10

VFlip_CalcBoardStats:
	; clear old stats
	ld hl, wVFlipRowStats
	ld bc, 5 * 4
	xor a
	call ByteFill

	; calc row stats
	ld de, wVFlipBoard
	ld hl, wVFlipRowStats
	ld b, 5
.loop_1_r
	ld c, 5
.loop_2_r
	ld a, [de]
	inc de
	and a
	jr z, .bomb_r
	add [hl]
	ld [hl], a
	jr .done_r
.bomb_r
	inc hl
	inc [hl]
	dec hl
.done_r
	dec c
	jr nz, .loop_2_r
	inc hl
	inc hl
	dec b
	jr nz, .loop_1_r

	; calc col stats
	ld de, wVFlipBoard
	ld b, 5
.loop_1_c
	ld c, 5
	ld hl, wVFlipColStats
.loop_2_c
	ld a, [de]
	inc de
	and a
	jr z, .bomb_c
	add [hl]
	ldi [hl], a
	inc hl
	jr .done_c
.bomb_c
	inc hl
	inc [hl]
	inc hl
.done_c
	dec c
	jr nz, .loop_2_c
	dec b
	jr nz, .loop_1_c
	ret

VFlip_DrawBoardStats:
	; rows
	hlcoord 17, 0
	ld de, wVFlipRowStats + 0
	lb bc, 1, 2
	call PrintNum
	hlcoord 17, 1
	ld de, wVFlipRowStats + 1
	lb bc, 1, 2
	call PrintNum
	hlcoord 17, 3
	ld de, wVFlipRowStats + 2
	lb bc, 1, 2
	call PrintNum
	hlcoord 17, 4
	ld de, wVFlipRowStats + 3
	lb bc, 1, 2
	call PrintNum
	hlcoord 17, 6
	ld de, wVFlipRowStats + 4
	lb bc, 1, 2
	call PrintNum
	hlcoord 17, 7
	ld de, wVFlipRowStats + 5
	lb bc, 1, 2
	call PrintNum
	hlcoord 17, 9
	ld de, wVFlipRowStats + 6
	lb bc, 1, 2
	call PrintNum
	hlcoord 17, 10
	ld de, wVFlipRowStats + 7
	lb bc, 1, 2
	call PrintNum
	hlcoord 17, 12
	ld de, wVFlipRowStats + 8
	lb bc, 1, 2
	call PrintNum
	hlcoord 17, 13
	ld de, wVFlipRowStats + 9
	lb bc, 1, 2
	call PrintNum
	; cols
	hlcoord 0, 16
	ld de, wVFlipColStats + 0
	lb bc, 1, 2
	call PrintNum
	hlcoord 0, 17
	ld de, wVFlipColStats + 1
	lb bc, 1, 2
	call PrintNum
	hlcoord 3, 16
	ld de, wVFlipColStats + 2
	lb bc, 1, 2
	call PrintNum
	hlcoord 3, 17
	ld de, wVFlipColStats + 3
	lb bc, 1, 2
	call PrintNum
	hlcoord 6, 16
	ld de, wVFlipColStats + 4
	lb bc, 1, 2
	call PrintNum
	hlcoord 6, 17
	ld de, wVFlipColStats + 5
	lb bc, 1, 2
	call PrintNum
	hlcoord 9, 16
	ld de, wVFlipColStats + 6
	lb bc, 1, 2
	call PrintNum
	hlcoord 9, 17
	ld de, wVFlipColStats + 7
	lb bc, 1, 2
	call PrintNum
	hlcoord 12, 16
	ld de, wVFlipColStats + 8
	lb bc, 1, 2
	call PrintNum
	hlcoord 12, 17
	ld de, wVFlipColStats + 9
	lb bc, 1, 2
	call PrintNum
	ret

VFlip_DrawCursor:
	; get cursor coordinates
	call VFlip_CursorToBC
	add a
	add c
	inc a
	ld h, a ; cursor x
	ld a, b
	add a
	add b
	inc a
	inc a
	ld l, a ; cursor y
	add hl, hl
	add hl, hl
	add hl, hl
	ld b, h
	ld c, l
	; b has sprite x, c has sprite y
	ld hl, .OAM_data
	call VFlip_CopyOAM
	ret

.OAM_data
	db 6
	dbsprite 0, 0, 0, 0, $02, 2
	dbsprite 1, 0, 0, 0, $04, 2
	dbsprite 2, 0, 0, 0, $02, 2 | X_FLIP
	dbsprite 0, 2, 0, 0, $06, 2
	dbsprite 1, 2, 0, 0, $08, 2
	dbsprite 2, 2, 0, 0, $06, 2 | X_FLIP

VFlip_CopyOAM:
	ld de, wVirtualOAMSprite00
	ldi a, [hl]
.loop
	push af
	ldi a, [hl]
	add c
	ld [de], a ; y
	inc de
	ldi a, [hl]
	add b
	ld [de], a ; x
	inc de
	ldi a, [hl]
	ld [de], a ; tile id
	inc de
	ldi a, [hl]
	ld [de], a ; attr
	inc de
	pop af
	dec a
	jr nz, .loop
	ret

VFlip_HideCursor:
	ld hl, wVirtualOAMSprite00YCoord
	ld a, SCREEN_HEIGHT_PX + 2 * TILE_WIDTH
	ld bc, SPRITEOAMSTRUCT_LENGTH
	ld d, 6 ; number of cursor oam's
.loop
	ld [hl], a
	add hl, bc
	dec d
	jr nz, .loop
	ret

VFlipAction_FinishWin:
	call VFlip_HideCursor
	call VFlip_DrawPayout
	ld de, SFX_3RD_PLACE
	call PlaySFX
	call WaitSFX

	ld a, [wVFlipLevel]
	ld [wVFlipOldLevel], a

	ld a, [wVFlipLevel]
	cp 8
	jr nc, .done_level_change
	ld a, [wVFlipCardsTurned]
	cp 8
	jr c, .try_increment_level
	ld a, [wVFlipComboCounter]
	inc a
	ld [wVFlipComboCounter], a
	cp 5
	jr nc, .set_level_8
	ld a, [wVFlipCardsTurned]
.try_increment_level
	ld b, a
	ld a, [wVFlipLevel]
	cp b
	jr nc, .done_level_change
	cp 7
	jr nc, .done_level_change
	inc a
	ld [wVFlipLevel], a
	jr .done_level_change

.set_level_8
	ld a, 8
	ld [wVFlipLevel], a
.done_level_change
	call VFlipAction_Next
	ret

VFlipAction_FinishLose:
	call VFlip_HideCursor
	call VFlip_DrawPayout
	ld de, SFX_QUIT_SLOTS
	call PlaySFX
	call WaitSFX

	xor a
	ld [wVFlipComboCounter], a
	ld a, [wVFlipCardsTurned]
	dec a
	ld b, a

	ld a, [wVFlipLevel]
	ld [wVFlipOldLevel], a

	cp b
	jr c, .done
	ld a, b
	and a
	jr nz, .no_inc
	inc a
.no_inc
	ld [wVFlipLevel], a
.done
	call VFlipAction_Next
	ret

VFlipAction_FinishAll:
	xor a
	ld [wPayout], a
	ld [wPayout + 1], a
	call VFlip_DrawPayout
	call VFlip_FlipAllCards

	call JoyWaitAorB

	ld a, [wVFlipOldLevel]
	ld b, a
	ld a, [wVFlipLevel]
	cp b
	jr z, .no_level_change
	jr nc, .level_up
	ld hl, .level_down_msg
	ld de, SFX_WRONG
	jr .new_level_msg

.level_up
	ld hl, .level_up_msg
	ld de, SFX_SLOT_MACHINE_START
.new_level_msg
	call PlaySFX
	call MenuTextbox
	call WaitBGMap2
	call WaitButton
	call ExitMenu
	call WaitSFX
.no_level_change
	ld a, VFLIP_ASK_PLAY
	ld [wJumptableIndex], a
	ret

.level_down_msg
	text "Dropped to"
	line "level @"
	text_decimal wVFlipLevel, 1, 1
	text "…"
	done

.level_up_msg
	text "Advanced to"
	line "level @"
	text_decimal wVFlipLevel, 1, 1
	text "!"
	done

VFlip_FlipAllCards:
	xor a
	ld [wVFlipCursorPos], a
	ld c, 25
.loop
	push bc
	call VFlip_TryFlipCard
	call c, VFlip_CardFlipAnimation
	pop bc
	ld hl, wVFlipCursorPos
	inc [hl]
	dec c
	jr nz, .loop
	call VFlip_HideCursor
	ret

VFlipAction_GivePayout:
	call .try_payout
	call .try_payout
	call .try_payout
	call .try_payout
	ldh a, [hVBlankCounter]
	and %11
	ret nz
	ld de, SFX_GET_COIN_FROM_SLOTS
	call PlaySFX
	call VFlip_DrawPayout
	ret

.try_payout
	ld hl, wPayout
	ldi a, [hl]
	ld d, a
	or [hl]
	jr z, .done
	ld e, [hl]
	dec de
	ld [hl], e
	dec hl
	ld [hl], d
	ld hl, wCoins
	ld d, [hl]
	inc hl
	ld e, [hl]
	call .check_coin_case_full
	jr c, .okay
	inc de
.okay
	ld [hl], e
	dec hl
	ld [hl], d
	ret

.done
	ld a, VFLIP_FINISH_UP
	ld [wJumptableIndex], a
	ret

.check_coin_case_full
	ld a, d
	cp HIGH(MAX_COINS)
	jr c, .not_full
	ld a, e
	cp LOW(MAX_COINS)
	jr c, .not_full
	scf
	ret

.not_full
	and a
	ret

VFlip_CardFlipAnimation:
	push af
	; update tilemap and attrmap for flipped card
	call VFlip_CursorToBC
	hlcoord 0, 0
	ld a, b
	ld b, 0
	add hl, bc
	add hl, bc
	add hl, bc
	ld bc, SCREEN_WIDTH * 3
	call AddNTimes
	push hl
	call .inc_box
	pop hl
	ld bc, wAttrmap - wTilemap
	add hl, bc
	ld a, 1
	lb bc, 3, 3
	push hl
	call FillBoxWithByte
	pop hl
	call .check_for_voltorb
	; get cursor coordinates
	call VFlip_CursorToBC
	add a
	add c
	inc a
	ld h, a ; cursor x
	ld a, b
	add a
	add b
	inc a
	inc a
	ld l, a ; cursor y
	add hl, hl
	add hl, hl
	add hl, hl
	ld b, h
	ld c, l
	; b has sprite x, c has sprite y
	ld hl, .sprite_frames
	ld d, 4
.loop
	push de
	ld a, d
	srl a
	call nc, .update_bgmapmode
	call VFlip_CopyOAM
	call DelayFrame
	call DelayFrame
	pop de
	dec d
	jr nz, .loop

	pop af
	ret

.update_bgmapmode
	ldh [hBGMapMode], a
	ret

.check_for_voltorb
	push hl
	ld a, [wVFlipCursorPos]
	ld c, a
	ld b, 0
	ld hl, wVFlipBoard
	add hl, bc
	ld a, [hl]
	and %00000011
	jr nz, .voltorb_check_done
	pop hl
	push hl
	ld bc, SCREEN_WIDTH + 1
	add hl, bc
	ld [hl], 2
.voltorb_check_done
	pop hl
	ret

.inc_box
	inc hl
	inc [hl]
	inc [hl]
	ld bc, SCREEN_WIDTH - 1
	add hl, bc
	inc [hl]
	inc [hl]
	inc hl
	inc hl
	inc [hl]
	inc [hl]
	add hl, bc
	inc [hl]
	inc [hl]
	ret

.sprite_frames
	db 6
	dbsprite 0, 0, 0, 0, $0a, 0
	dbsprite 1, 0, 0, 0, $0c, 0
	dbsprite 2, 0, 0, 0, $0a, 0 | X_FLIP
	dbsprite 0, 2, 0, 0, $20, 0
	dbsprite 1, 2, 0, 0, $22, 0
	dbsprite 2, 2, 0, 0, $20, 0 | X_FLIP

	db 6
	dbsprite 0, 0, 0, 0, $0e, 0
	dbsprite 1, 0, 0, 0, $10, 0
	dbsprite 2, 0, 0, 0, $0e, 0
	dbsprite 0, 2, 0, 0, $24, 0
	dbsprite 1, 2, 0, 0, $26, 0
	dbsprite 2, 2, 0, 0, $24, 0

	db 6
	dbsprite 0, 0, 0, 0, $0e, 1
	dbsprite 1, 0, 0, 0, $12, 1
	dbsprite 2, 0, 0, 0, $0e, 1
	dbsprite 0, 2, 0, 0, $24, 1
	dbsprite 1, 2, 0, 0, $28, 1
	dbsprite 2, 2, 0, 0, $24, 1

	db 6
	dbsprite 0, 0, 0, 0, $0a, 1
	dbsprite 1, 0, 0, 0, $14, 1
	dbsprite 2, 0, 0, 0, $0a, 1 | X_FLIP
	dbsprite 0, 2, 0, 0, $20, 1
	dbsprite 1, 2, 0, 0, $2a, 1
	dbsprite 2, 2, 0, 0, $20, 1 | X_FLIP

VoltorbFlipSpriteGFX:
	INCBIN "gfx/voltorb_flip/sprite_tiles.2bpp.lz"

VoltorbFlipTileGFX:
	INCBIN "gfx/voltorb_flip/bg_tiles.2bpp.lz"

VoltorbFlipTilemap:
	INCBIN "gfx/voltorb_flip/background.tilemap"

VoltorbFlipAttrmap:
	INCBIN "gfx/voltorb_flip/background.attrmap"
