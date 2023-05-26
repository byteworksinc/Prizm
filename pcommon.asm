	mcopy	PCommon.macros
****************************************************************
*
*  SetMenuState - Highlight menus based on the program state
*                 
*  Inputs:
*	state - new menu state
*
****************************************************************
*
SetMenuState start
!			menu states
nullMenu	equ	0	null state
noWindow	equ	1	no windows
sysWindow equ	2	front window is a system window
execMenu	equ	3	executing a program
specWindow equ	4	front window is special
noSelections equ 5	front window is text; no selections
fullMenu	equ	6	front window is text; text selected

appleMenu equ	1	menu numbers
fileMenu	equ	2
editMenu	equ	3
windowsMenu equ 4
findMenu	equ	5
extrasMenu equ	6
runMenu	equ	7
debugMenu equ	8
languagesMenu equ 9

mask	equ	0	state and mask
menu	equ	2	loop/index variable
redraw	equ	4	redraw the menu?

	subroutine (2:state),6

	lda	oldState	if state = oldState then
	cmp	state
	jeq	ret	  return

	lda	#1	set the state and mask
	ldx	state
	beq	lb2
lb1	asl	A
	dex
	bne	lb1
lb2	sta	mask

	stz	redraw	redraw := false
	lda	#languagesMenu-1	for menu := languagesMenu downto
	sta	menu	  appleMenu do
lb3	ldy	#0	  if menu flag differs for old/new state
	ldx	menu	    then
	lda	menuFlags,X
	bit	mask
	beq	lb4
	iny
lb4	phy
	ldy	#0
	bit	oldMask
	beq	lb5
	iny
lb5	tya
	eor	1,S
	ply
	tay
	beq	lb7
	ldy	#$FF7F	    set the menu state
	lda	menuFlags,X
	and	mask
	bne	lb6
	ldy	#$0080
lb6	phy
	lda	menu
	inc	A
	pha
	_SetMenuFlag
	inc	redraw	    redraw = true
lb7	dec	menu	next menu
	dec	menu
	bpl	lb3
	lda	redraw	if redraw then
	beq	lb8
	_DrawMenuBar	  redraw the menu bar
lb8	anop

	stz	menu	for each menu item do
mm1	ldx	menu
	lda	itemFlags+1,X
	beq	mm4
	pha		  enable/disable item
	lda	itemFlags,X
	and	mask
	beq	mm2
	_EnableMItem
	bra	mm3
mm2	_DisableMItem
mm3	clc		next menu item
	lda	menu
	adc	#3
	sta	menu
	bra	mm1
mm4	anop

	lda	state	oldState = state
	sta	oldState
	lda	mask	oldMask = mask
	sta	oldMask

	jsl	CheckMenuItems	set the volatile menu items

ret	return

oldState	ds	2	old menu state
oldMask	ds	2	old state and mask

menuFlags anop		state flags for full menus
	dc	b'0111 0111'	appleMenu
	dc	b'0111 0111'	fileMenu
	dc	b'0110 0101'	editMenu
	dc	b'0111 1111'	windowsMenu
	dc	b'0110 0001'	findMenu
	dc	b'0111 0111'	extrasMenu
	dc	b'0111 0111'	runMenu
	dc	b'0111 1111'	debugMenu
	dc	b'0110 0001'	languagesMenu

itemFlags anop		state flags for menu items
	dc	b'0111 0111',i'257'	apple_About

	dc	b'0111 0111',i'260'	file_New
	dc	b'0111 0111',i'261'	file_Open
	dc	b'0111 0101',i'255'	file_Close
	dc	b'0110 0001',i'263'	file_Save
	dc	b'0110 0001',i'264'	file_SaveAs
	dc	b'0110 0001',i'265'	file_RevertToSaved
	dc	b'0111 0111',i'270'	file_PageSetup
	dc	b'0110 0001',i'272'	file_Print
	dc	b'0111 0111',i'273'	file_Quit

	dc	b'0110 0101',i'250'	edit_Undo
	dc	b'0100 0101',i'251'	edit_Cut
	dc	b'0100 0101',i'252'	edit_Copy
	dc	b'0110 0101',i'253'	edit_Paste
	dc	b'0100 0101',i'254'	edit_Clear
	dc	b'0110 0001',i'285'	edit_SelectAll

	dc	b'0110 0001',i'300'	windows_Tile
	dc	b'0110 0001',i'301'	windows_Stack
	dc	b'0111 1111',i'302'	windows_Shell
	dc	b'0111 1111',i'543'	run_GraphicsWindow
	dc	b'0111 1111',i'559'	debug_Variables

	dc	b'0110 0001',i'520'	find_Find
	dc	b'0110 0001',i'521'	find_FindSame
	dc	b'0110 0001',i'522'	find_DisplaySelection
	dc	b'0110 0001',i'523'	find_Replace
	dc	b'0110 0001',i'524'	find_ReplaceSame
	dc	b'0110 0001',i'525'	find_Goto
 
	dc	b'0110 0001',i'530'	extras_ShiftLeft
	dc	b'0110 0001',i'531'	extras_ShiftRight
	dc	b'0110 0001',i'532'	extras_DeleteToEndOfLine
	dc	b'0110 0001',i'533'	extras_JoinLines
	dc	b'0110 0001',i'534'	extras_InsertLine
	dc	b'0110 0001',i'535'	extras_DeleteLine
	dc	b'0110 0001',i'536'	extras_AutoIndent
	dc	b'0110 0001',i'537'	extras_OverStrike
	dc	b'0110 0001',i'538'	extras_ShowRuler
	dc	b'0111 0111',i'539'	extras_AutoSave
 
	dc	b'0110 0001',i'540'	run_CompileToMemory
	dc	b'0110 0001',i'541'	run_CompileToDisk
	dc	b'0110 0001',i'542'	run_CheckForErrors
	dc	b'0111 0111',i'544'	run_Compile
	dc	b'0111 0111',i'545'	run_Link
	dc	b'0111 0111',i'546'	run_Execute
	dc	b'0111 0111',i'547'	run_ExecuteOptions
 
	dc	b'0110 1001',i'550'	debug_Step
	dc	b'0000 1001',i'551'	debug_StepThru
	dc	b'0110 1001',i'552'	debug_Trace
	dc	b'0110 1001',i'553'	debug_Go
	dc	b'0000 1001',i'554'	debug_GoToNextReturn
	dc	b'0000 1001',i'555'	debug_Stop
	dc	b'0111 0111',i'556'	debug_Profile
	dc	b'0110 0001',i'557'	debug_SetClearBreakPoint
	dc	b'0110 0001',i'558'	debug_SetClearAutoGo

	dc	b'0000 0000',i'0'	end of list
	end
