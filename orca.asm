	mcopy orca.macros
****************************************************************
*
*  TrackCursor - Change the cursor based on screen position
*
*  Inputs:
*	h,v - mouse position in local coordinates
*	width - width of screen, in characters
*	height - height of screen, in pixels
*	redraw - redraw the cursor, reguardless of knowledge of need
*
****************************************************************
*
TrackCursor start
standard equ	0	cursor types
reverseArrow equ 1
insertion equ	2

	subroutine (2:v,2:h,2:width,2:height,2:redraw),0

	phb		use local data
	phk
	plb
	lda	>frWPtr	if frWPtr <> nil then
	ora	>frWPtr+2
	beq	fr1
	pha		  if frWPtr = FrontWindow then
	pha
	_FrontWindow
	pla
	plx
	cmp	>frWPtr
	bne	fr1
	txa
	cmp	>frWPtr+2
	bne	fr1
	ph4	>lastEvent+10	    if ReplaceIBeam then
	jsl	ReplaceIBeam
	tax
	beq	fr0
	lda	#insertion	      want I-Beam
	bra	lb4	    else
fr0	lda	#standard	      want arrow
	bra	lb4

fr1	pha		if FrontWindow <> currentFile.wptr
	pha		  or (h < 0) or (h >= width*8+1)
	_FrontWindow	  or (v < 0) or (v >= height) then
	pla
	plx
	cmp	currentFile
	bne	lb1
	cpx	currentFile+2
	bne	lb1
	lda	h
	bmi	lb1
	lsr	a
	lsr	a
	lsr	a
	inc	width
	cmp	width
	bge	lb1
	lda	v
	bmi	lb1
	cmp	height
	blt	lb2
lb1	lda	#standard	  we want the standard cursor
	bra	lb4
lb2	lda	h	else if h < 8 then
	cmp	#8
	bge	lb3
	lda	#reverseArrow	  we want the reverse arrow cursor
	bra	lb4	else
lb3	lda	#insertion	  we want the insertion cursor
lb4	ldx	redraw	if redraw the skip quit check
	bne	lb4a
	cmp	cursorKind	quit now if we have what we want
	beq	lb8
lb4a	sta	cursorKind	save the cursor kind
	cmp	#standard	if standard then
	bne	lb5
	_InitCursor	  use standard cursor
	bra	lb8	else if insertion then
lb5	cmp	#insertion
	bne	lb6
	_IBeamCursor	  use the I-beam cursor
	bra	lb8
lb6	ph4	#reverseCursor	else
	_SetCursor	  use the left arrow cursor
lb8	plb		restore data bank
	return

cursorKind dc	i'standard'	current cursor kind

reverseCursor anop
	dc	i'11,3'	reverse arrow cursor
	dc	h'000000000000'
	dc	h'0000000C0000'
	dc	h'0000003C0000'
	dc	h'000000FC0000'
	dc	h'000003FC0000'
	dc	h'00000FFC0000'
	dc	h'00003FFC0000'
	dc	h'0000FFFC0000'
	dc	h'00000F3C0000'
	dc	h'00003C000000'
	dc	h'000000000000'

	dc	h'0000000F0000'
	dc	h'0000003F0000'
	dc	h'000000FF0000'
	dc	h'000003FF0000'
	dc	h'00000FFF0000'
	dc	h'00003FFF0000'
	dc	h'0000FFFF0000'
	dc	h'0003FFFF0000'
	dc	h'0000FFFF0000'
	dc	h'0000FF3F0000'
	dc	h'0000FC000000'

	dc	i'1,14'
	end

****************************************************************
*
*  WakeUp - Read the initialization file
*
****************************************************************
*
WakeUp	start
	using BufferCommon

isTemp	equ	0	is this the temp file?
ptr	equ	2	pointer to the file
disp	equ	6	disp into window arrays
cnt	equ	8	loop counter
wh	equ	10	window handle
tptr	equ	14	temp copy of ptr

	subroutine ,18
;
;  load the file
;
	stz	isTemp	not the temp file
	stz	ffAction	try to load the temp file
	lda	#$C000
	sta	ffFlags
	lla	ffPathName,ORCA_TEMP
	tdc
	FastFileGS ffPCount
	bcs	lb1
	lla	ffPathName,ORCA_TEMP	success -> set path name & branch
	inc	isTemp	this is the temp file
	bra	lb2
lb1	lla	ffPathName,ORCA_CONFIG	try the default config file
	FastFileGS ffPCount
	jcs	rts
	lla	ffPathName,ORCA_CONFIG	success -> set path name for purge
lb2	anop
;
;  read the scalars from the file
;
	move4	ffFileHandle,ptr	dereference the handle
	ldy	#2
	lda	[ptr],Y
	tax
	lda	[ptr]
	sta	ptr
	stx	ptr+2
	lda	[ptr]	read scalars
	sta	autoSave
	ldy	#2
	lda	[ptr],Y
	sta	compileList
	iny
	iny
	lda	[ptr],Y
	sta	compileSymbol
	iny
	iny
	lda	[ptr],Y
	sta	compileDebug
	iny
	iny
	lda	[ptr],Y
	sta	compileLink
	iny
	iny
	lda	[ptr],Y
	sta	linkList
	iny
	iny
	lda	[ptr],Y
	sta	linkSymbol
	iny
	iny
	lda	[ptr],Y
	sta	linkSave
	iny
	iny
	lda	[ptr],Y
	sta	linkExecute
	iny
	iny
	lda	[ptr],Y
	sta	fileKind
	iny
	iny
	lda	[ptr],Y
	sta	profile
;
;  set standard prefixes
;
	add4	ptr,#24,prefix	set prefix 8
	lda	#8
	sta	prefixNum
	SetPrefixGS prDCB
	add4	prefix,#260	set prefix 13
	lda	#13
	sta	prefixNum
	SetPrefixGS prDCB
	add4	prefix,#260	set prefix 16
	lda	#16
	sta	prefixNum
	SetPrefixGS prDCB
;
;  open the user windows
;
	add4	ptr,#802,tptr	set pointer for system windows
	add4	ptr,#822	set pointer for user windows
uw1	lda	[ptr]	while ptr^ <> 0 do begin
	beq	uw3
	add4	ptr,#12,giName	  skip if the file has been deleted
	GetFileInfoGS giDCB
	bcs	uw2a
	ldy	#2	  OpenNewWindow(ptr[2],ptr[4],ptr[6],
	ldx	#4	    ptr[8],@ptr[12]);
uw2	lda	[ptr],Y
	pha
	iny
	iny
	dex
	bne	uw2
	clc
	lda	ptr
	adc	#12
	tax
	lda	ptr+2
	adc	#0
	pha
	phx
	jsl	OpenNewWindow
	ldy	#10	  set the language
	lda	[ptr],Y
	sta	currentFile+language
uw2a	add4	ptr,#12+258	  ptr += 12+258;
	bra	uw1
uw3	anop
;
;  open the standard windows
;
	stz	disp	disp := 0;
	lda	#2	for cnt := 1 to 2 do begin
	sta	cnt
sw1	lda	[tptr]	  if tptr^ <> 0 then begin
	beq	sw2
	ldy	disp	    open the window
	lda	wsubs,Y
	sta	jsl+1
	lda	wsubs+1,Y
	sta	jsl+2
	ora	jsl+1
	beq	sw2
jsl	jsl	jsl
	ldy	#2	    move the window to the old spot
	lda	[tptr],Y
	pha
	iny
	iny
	lda	[tptr],Y
	pha
	ldx	disp
	lda	wptrs+2,X
	sta	wh+2
	lda	wptrs,X
	sta	wh
	ldy	#2
	lda	[wh],Y
	pha
	lda	[wh]
	pha
	_MoveWindow
	ldy	#6	    set the window size
	lda	[tptr],Y
	pha
	iny
	iny
	lda	[tptr],Y
	pha
	ldy	#2
	lda	[wh],Y
	pha
	lda	[wh]
	pha
	_SizeWindow
sw2	anop		    end; {if}
	add2	disp,#4	  disp += 4;
	add4	tptr,#10	  update pointer
	dec	cnt	next window
	bne	sw1
;
;  purge the file
;
	lda	#7	purge the file
	sta	ffAction
	FastFileGS ffPCount
	lda	isTemp	if this is the temp file then
	beq	rts
	move4 ffPathName,dsPathname	  delete it
	DestroyGS dsDCB
rts	return

ORCA_TEMP entry
	dosw	'9/PRIZM.TEMP'
ORCA_CONFIG entry
	dosw	'9/PRIZM.CONFIG'

dsDCB	dc	i'1'	destroy dcb
dsPathname ds	4

giDCB	dc	i'4'	get file info DCB
giName	ds	4
	ds	2+2+4

prDCB	dc	i'2'	set prefix DCB
prefixNum ds	2
prefix	ds	4

wptrs	entry		pointer table for system windows
	dc	a4'grPtr,vrPtr,0'

wsubs	anop		pointer table to window init subroutines
	dc	a4'DoGraphics,DoVariables'

ffPCount	dc	i'14'	FastFile DCB
ffAction ds	2
ffIndex	ds	2
ffFlags	ds	2
ffFileHandle ds 4
ffPathName ds	4
ffAccess	ds	2
ffFileType ds	2
ffAuxType ds	4
ffStorageType ds 2
ffCreateDate ds 8
ffModDate ds	8
ffOption	ds	4
ffFileLength ds 4
bbBlocksUsed ds 4
	end
