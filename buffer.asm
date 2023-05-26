	mcopy buffer.macros
****************************************************************
*
*  BufferCommon - Common data area
*
****************************************************************
*
BufferCommon data
;
;  Key codes
;
RETURN	equ	13
TAB	equ	9
oldBreakChar equ $84	old break character
oldSkipChar equ $81	old skip character
newBreakChar equ $07	new break character
newSkipChar equ $06	new skip character
stepChar	equ	$05	step arrow character
;
;  Displacements into the currentFile variable
;
wPtr	equ	0	pointer to the window
vScroll	equ	wPtr+4	control handles
hScroll	equ	vScroll+4
grow	equ	hScroll+4

buffHandle equ grow+4	handle of the buffer
buffStart equ	buffHandle+4	start, end of the buffer
buffEnd	equ	buffStart+4
gapStart equ	buffEnd+4	first free byte in gap
pageStart equ	gapStart+4	first character on the display
buffSize equ	pageStart+4	size of buffer, in bytes
expanded equ	buffSize+4	tells if the buffer is expanded

isFile	equ	expanded+2	is there an existing file?
fileName equ	isFile+2	file name (if any)
pathName equ	fileName+34	path name (if any)
changed	equ	pathName+256	has the file changed since saving?

cursor	equ	changed+2	points to char cursor is on or before
cursorColumn equ cursor+4	screen position of cursor
cursorRow equ	cursorColumn+2
width	equ	cursorRow+4	screen width, height, in characters
height	equ	width+2
maxHeight equ	height+2	height of main & split screen
numLines equ	maxHeight+2	# lines in the file
topLine	equ	numLines+4	top line on the screen
leftColumn equ topLine+4	leftmost column on display
dispFromTop equ leftColumn+2	disp from top of first line

select	equ	dispFromTop+2	if selection, this is the end of the
!			 selected text - cursor is the other
selection equ	select+4	is there an active selection?

splitScreen equ selection+2	is the screen split?
topLineAlt equ splitScreen+2	line # of top line on alt screen
heightAlt equ	topLineAlt+4	height of alternate screen
vScrollAlt equ heightAlt+2	alt screen scroll bar
dispFromTopAlt equ vScrollAlt+4	disp from top in pixels
splitScreenRect equ dispFromTopAlt+2	split screen control location

showRuler equ	splitScreenRect+8	is the ruler visible?}
ruler	equ	showRuler+2	ruler - 1 -> tab stop; 0 -> no code}

newDebug	equ	ruler+256	new debug characters? (or old)
insert	equ	newDebug+2	insert? (or overstrike)
autoReturn equ insert+2	return to first non-blank?
language equ	autoReturn+2	language number

last	equ	language+2	pointer to last buffer
next	equ	last+4	pointer to next buffer

changesSinceCompile equ next+4	changes since last compile?
exeName	equ	changesSinceCompile+2	name of executable file
undoList equ	exeName+256	head of undo list
verticalMove equ undoList+4	was the last key a vertical move?
vCursorColumn equ verticalMove+2	cursorColumn before vertical move

buffLength equ vCursorColumn+2	length of buffer
;
;  Line drawing variables
;
locRec	dc	i1'$80'	info about the object to draw
	dc	i1'0'
charAddr dc	a4'line1'
	dc	i'77*2'
	dc	i'0,0,8,77*8'

rect	dc	i'0,0,8,8'	size of rectangle to draw it in
point	ds	4	work point
breakChar dc	i'newBreakChar'	current break-point character
skipChar	dc	i'newSkipChar'	current auto-go character

line1	ds	77*2	line buffers
line2	ds	77*2
line3	ds	77*2
line4	ds	77*2
line5	ds	77*2
line6	ds	77*2
line7	ds	77*2
line8	ds	77*2
	end

****************************************************************
*
*  Check255 - make sure the current line is < 256 chars long
*
****************************************************************
*
Check255 start
lcursor	equ	1	local copy of the cursor

	using BufferCommon

	phd		set up work space
	pha
	pha
	tsc
	tcd

	move4	currentFile+cursor,oldCursor save the old cursor
	jsl	MoveToStart	see if the line is tool long
	move4 currentFile+cursor,lcursor
	ldy	#0
	tyx
	short M
lb1	lda	[lcursor],Y
	cmp	#RETURN
	beq	lb2
	cmp	#tab
	bne	tb2
tb1	inx
	lda	currentFile+ruler,X
	beq	tb1
	dex
tb2	inx
	cpx	#256
	bge	lb3
	iny
	bra	lb1

lb2	long	M	line is OK - restore cursor & return
	move4	oldCursor,currentFile+cursor
	bra	lb7

lb3	long	M	push the source address
	clc
	tya
	adc	lcursor
	sta	lcursor
	bcc	dc1
	inc	lcursor+2
dc1	ph4	lcursor
	ldy	#-1	find the number of bytes being deleted
	short	M
dc2	iny
	lda	[lcursor],Y
	cmp	#return
	bne	dc2
	long	M
	clc		update cursor
	tya
	adc	oldCursor
	sta	oldCursor
	bcc	dc3
	inc	oldCursor+2
dc3	clc		push the destination address
	tya
	adc	lcursor
	tax
	lda	#0
	adc	lcursor+2
	pha
	phx
	sub4	lcursor,currentFile+pageStart push the # of bytes to delete
	ph4	lcursor
	jsl	MoveForward	delete the bytes
	move4	oldCursor,currentFile+cursor restore the cursor
	jsl	FindCursorColumn	update cursorColumn
	sta	currentFile+cursorColumn

lb7	pla		remove work space & return
	pla
	pld
	rtl

oldCursor ds	4	old cursor value
	end

****************************************************************
*
*  DrawMark - draw the line marker
*
*  Inputs:
*	ch - character number
*	v - row #
*	dispFromTop - pixels from top to first row
*
****************************************************************
*
DrawMark start
	using BufferCommon

	subroutine (2:ch,2:v,2:dispFromTop),0

	lda	ch	write the tab (or erase an old one)
	asl	a
	asl	a
	asl	a
	asl	a
	clc
	adc	#characters
	sta	iconAddr
	ph4	#iconRc	write the stuff
	ph4	#iRec
	ph2	#0
	lda	v
	asl	a
	asl	a
	asl	a
	inc	a
	clc
	adc	dispFromTop
	pha
	ph2	#0
	_PPToPort
	return

iconRc	dc	i1'$80'	info about the object to draw
	dc	i1'0'
iconAddr dc	a4'characters'
	dc	i'2'
iRec	dc	i'0,0,8,8'
	end

****************************************************************
*
*  DrawOneLine - Redraw a line on a non-split screen
*
*  Inputs:
*	line - line number of line to draw
*
****************************************************************
*
DrawOneLine start
	using BufferCommon
selectStart equ 0	start disp of selected text
selectEnd equ	4	end disp of selected text
startPtr equ	8	ptr to first char to be drawn

numChars equ	8	max # of characters
cp	equ	10	character pointer
disp	equ	14	disp into character array
yDisp	equ	16	y disp into window, in pixels
col	equ	18	column #
startChar equ	20	char in col 0

numBlanks equ	22	number of blanks left in tab field
tabIndex	equ	24	index into tab line

	subroutine (2:line),26
;
;  Decide which method to use
;
!			Common initialization...
	jsr	SetCharacters	get the current breakpoint and auto-go characters
	_HideCursor
	stz	point	get the location of the top left byte
	stz	point+2
	ph4	#point
	_LocalToGlobal
	move4 currentFile+pageStart,startPtr set the selection displacements
	jsr	SetSelection
	lda	line	quit if off of screen
	cmp	currentFile+height
	jge	en1
	sec		set numChars to the number of characters
	lda	currentFile+buffEnd	 available, or to 65535, whichever is
	sbc	currentFile+pageStart	 smaller
	sta	numChars
	lda	currentFile+buffEnd+2
	sbc	currentFile+pageStart+2
	beq	dc1
	lda	#$FFFF
	sta	numChars

dc1	move4 currentFile+pageStart,cp index in by the proper # of lines
	ldy	#0
	ldx	line
	beq	dc5
	short M
	lda	#return
dc2	cmp	[cp],Y
	bne	dc3
	dex
	beq	dc4
dc3	iny
	cpy	numChars
	blt	dc2
	dey
	dey
dc4	iny
dc5	long	M
	lda	#' '	set the start character
	sta	startChar
	lda	[cp],Y
	and	#$00FF
	cmp	breakChar
	beq	dc5a
	cmp	skipChar
	bne	dc5b
dc5a	sta	startChar
	iny
dc5b	stz	tabIndex	set up tab counters
	stz	numBlanks
	ldx	currentFile+leftColumn	index in by leftColumn characters
	beq	dc7
dc6	lda	numBlanks
	bne	aa1
	lda	[cp],Y
	and	#$00FF
	cmp	#return
	beq	dc7
	cmp	#tab
	bne	aa2
	jsr	CountTabs
	iny
aa1	dec	numBlanks
	dey
aa2	iny
	inc	tabIndex
	dex
	bne	dc6
dc7	sty	disp
	long	M
	pha		use QuickDraw if we are not drawing
	pha		 in the front window
	_FrontWindow
	pla
	plx
	cmp	currentFile+wPtr
	bne	qd1
	cpx	currentFile+wPtr+2
	bne	qd1
	jsr	OnScreen
	jcs	fs1
;
;  Use QuickDraw
;
qd1	lda	currentFile+cursorRow	set disp into the window
	asl	a
	asl	a
	asl	a
	sec
	adc	currentFile+dispFromTop
	sta	yDisp
	lda	currentFile+width	set width of drawing rectangle
	inc	a
	asl	a
	asl	a
	asl	a
	sta	rect+6
	lda	startChar	set first character
	jsr	SetFirst
	ldx	#0	set disp into line array
	stz	col	column # is 0
lb2	ldy	disp	get the next char to write
	lda	numBlanks
	beq	bb1
	dec	numBlanks
	dec	disp
	lda	#' '
	bra	bb2
bb1	lda	[cp],Y
	and	#$00FF
	cmp	#RETURN
	jeq	lb3
	cmp	#tab
	bne	bb2
	jsr	CountTabs
	inc	disp
	bra	lb2
bb2	asl	a	convert to disp into character bit maps
	asl	a
	asl	a
	asl	a
	cpy	selectStart	branch if not in selection
	blt	lb2b
	cpy	selectEnd	if at end of selection, use normal
	blt	lb2a	 characters
	lda	#$FFFF
	sta	selectStart
	bra	lb2b
lb2a	tay		place inverted char in line buffer
	lda	characters,Y
	eor	#$FFFF
	sta	line1+2,X
	lda	characters+2,Y
	eor	#$FFFF
	sta	line2+2,X
	lda	characters+4,Y
	eor	#$FFFF
	sta	line3+2,X
	lda	characters+6,Y
	eor	#$FFFF
	sta	line4+2,X
	lda	characters+8,Y
	eor	#$FFFF
	sta	line5+2,X
	lda	characters+10,Y
	eor	#$FFFF
	sta	line6+2,X
	lda	characters+12,Y
	eor	#$FFFF
	sta	line7+2,X
	lda	characters+14,Y
	eor	#$FFFF
	sta	line8+2,X
	bra	lb2c
lb2b	tay		place character in line buffer
	lda	characters,Y
	sta	line1+2,X
	lda	characters+2,Y
	sta	line2+2,X
	lda	characters+4,Y
	sta	line3+2,X
	lda	characters+6,Y
	sta	line4+2,X
	lda	characters+8,Y
	sta	line5+2,X
	lda	characters+10,Y
	sta	line6+2,X
	lda	characters+12,Y
	sta	line7+2,X
	lda	characters+14,Y
	sta	line8+2,X
lb2c	inc	disp	update disp into character table
	inx		update disp into lines
	inx
	inc	tabIndex	update disp into tab line
	inc	col	update column number
	lda	col
	cmp	currentFile+width
	jlt	lb2
	bra	lb5
lb3	lda	#$FFFF	write spaces to the end of the line
	ldy	disp
	cmp	selectStart
	blt	lb3a
	cmp	selectEnd
	bge	lb3a
	lda	#0
lb3a	ldy	col
lb4	cpy	currentFile+width
	bge	lb5
	sta	line1+2,X
	sta	line2+2,X
	sta	line3+2,X
	sta	line4+2,X
	sta	line5+2,X
	sta	line6+2,X
	sta	line7+2,X
	sta	line8+2,X
	inx
	inx
	iny
	bra	lb4
lb5	ph4	#locRec	write the line
	ph4	#rect
	lda	point+2
	and	#$0003
	pha
	ph2	yDisp
	ph2	#0
	_PPToPort
	brl	en1
;
;  Use the 'fast' draw
;
fs1	lda	line	add in 8*line count
	asl	a
	asl	a
	asl	a
	clc
	adc	point
	sec		multiply Y+1+dipFromtop by 160
	adc	currentFile+dispFromTop
	ldx	#160
	jsl	~mul2
	sta	yDisp	add in x disp div 4 + 2
	lda	point+2
	inc	a
	inc	a
	inc	a
	lsr	a
	lsr	a
	inc	a
	sec
	adc	yDisp
	sta	yDisp	...result is initial disp in line

	lda	startChar
	ldx	yDisp
	jsr	SetFirstFast
	stz	col	  col := 0;
	ldx	yDisp	  X := yDisp;
fs2	ldy	col	  while (startChar[disp] <> return)
	cpy	currentFile+width	    and (col < w) do begin
	jeq	fs3
	ldy	disp
	lda	numBlanks
	beq	dd1
	dec	numBlanks
	dec	disp
	lda	#' '
	bra	dd2
dd1	lda	[cp],Y
	and	#$00FF
	cmp	#return
	jeq	fs3
	cmp	#tab
	bne	dd2
	jsr	CountTabs
	inc	disp
	bra	fs2
dd2	asl	a	    <write char to screen>
	asl	a
	asl	a
	asl	a
	cpy	selectStart	branch if not in selection
	blt	fs2b
	cpy	selectEnd	if at end of selection, use normal
	blt	fs2a	 characters
	lda	#$FFFF
	sta	selectStart
	bra	fs2b
fs2a	tay		place inverted char on screen
	lda	characters,Y
	eor	#$FFFF
	sta	$E12000,X
	lda	characters+2,Y
	eor	#$FFFF
	sta	$E12000+160,X
	lda	characters+4,Y
	eor	#$FFFF
	sta	$E12000+320,X
	lda	characters+6,Y
	eor	#$FFFF
	sta	$E12000+480,X
	lda	characters+8,Y
	eor	#$FFFF
	sta	$E12000+640,X
	lda	characters+10,Y
	eor	#$FFFF
	sta	$E12000+800,X
	lda	characters+12,Y
	eor	#$FFFF
	sta	$E12000+960,X
	lda	characters+14,Y
	eor	#$FFFF
	sta	$E12000+1120,X
	bra	fs2c
fs2b	tay		place normal char on screen
	lda	characters,Y
	sta	$E12000,X
	lda	characters+2,Y
	sta	$E12000+160,X
	lda	characters+4,Y
	sta	$E12000+320,X
	lda	characters+6,Y
	sta	$E12000+480,X
	lda	characters+8,Y
	sta	$E12000+640,X
	lda	characters+10,Y
	sta	$E12000+800,X
	lda	characters+12,Y
	sta	$E12000+960,X
	lda	characters+14,Y
	sta	$E12000+1120,X
fs2c	inx		    X += 2
	inx
	inc	tabIndex	    tabIndex++;
	inc	col	    col++;
	inc	disp	    disp++
	brl	fs2	    end; {while}
fs3	anop		1:
	sec		  while col < width do begin
	lda	currentFile+width	    <write ' ' to screen>
	sbc	col	    ++col;
	bmi	en1	    end; {while}
	beq	en1
	tay
	lda	disp
	cmp	selectStart
	blt	fs3a
	cmp	selectEnd
	bge	fs3a
	lda	#0
	bra	fs4
fs3a	lda	#$FFFF
fs4	sta	$E12000,X
	sta	$E12000+160,X
	sta	$E12000+320,X
	sta	$E12000+480,X
	sta	$E12000+640,X
	sta	$E12000+800,X
	sta	$E12000+960,X
	sta	$E12000+1120,X
	inx
	inx
	dey
	bne	fs4
;
;  Return to the caller
;
en1	_ShowCursor
	_ObscureCursor
	return
;
;  CountTabs - count the blanks to insert for this tab
;
CountTabs anop
	phx		save caller's regs
	phy
	ldy	tabIndex
	ldx	#0
ct1	inx
	iny
	cpy	#256
	bge	ct2
	lda	currentFile+ruler,Y
	and	#$00FF
	beq	ct1
ct2	stx	numBlanks
	ply
	plx
	rts
	end

****************************************************************
*
*  DrawOneScreen - Redraw one of the screens - either the main or the split
*
*  Inputs:
*	w,h - width, height of the screen, in characters
*	dispFromTop - # pixels to space down for first line
*	left - leftmost column on display
*	startChar - pointer to first char on the screen
*	maxChar - pointer to one past the last valid character
*	wp - pointer to window to draw in
*	tabs - pointer to the tab line
*
****************************************************************
*
DrawOneScreen start
	using BufferCommon
selectStart equ 0	start disp of selected text
selectEnd equ	4	end disp of selected text
startPtr equ	8	ptr to first char to be drawn

col	equ	8	column #
row	equ	10	row #
disp	equ	12	disp into character array
yDisp	equ	14	y disp into window, in pixels
numChars equ	16	max # of characters

grafDisp equ	10	disp into graphics screen
leftLoop equ	18	left edge loop counter

tabIndex	equ	20	index into tab line
numBlanks equ	22	number of blanks in the tab field
port	equ	24	grafPort on entry

       subroutine (2:w,2:h,2:lDispFromTop,2:left,4:startChar,4:maxChar,4:wp,4:tabs),28
;
;  Decide which method to use
;
!			Common initialization...
	jsr	SetCharacters	get the current breakpoint and auto-go characters
	lda	disableScreenUpdates
	jne	en2
	_HideCursor	hide the cursor
	pha		make this port active
	pha
	_GetPort
	pl4	port
	ph4	wp
	_SetPort
	stz	point	get the location of the top left byte
	stz	point+2
	ph4	#point
	_LocalToGlobal
	move4 startChar,startPtr	set the selection displacements
	jsr	SetSelection
	sec		set numChars to the number of characters
	lda	maxChar	 available, or to 65535, whichever is
	sbc	startChar	 smaller
	sta	numChars
	lda	maxChar+2
	sbc	startChar+2
	beq	dc1
	lda	#$FFFF
	sta	numChars

dc1	pha		use QuickDraw if we are not drawing
	pha		 in the front window
	_FrontWindow
	pla
	plx
	cmp	wp
	bne	qd1
	cpx	wp+2
	bne	qd1
	jsr	OnScreen
	jcs	fs1
;
;  Use QuickDraw
;
qd1	stz	disp	disp past startChar is 0
	lda	lDispFromTop	disp from top of window is
	inc	a	  1+lDispFromTop
	sta	yDisp
	stz	row	row number is 0
	lda	w	set width of drawing rectangle
	inc	a
	asl	a
	asl	a
	asl	a
	sta	rect+6
lb1	stz	col	column number is 0
	ldy	disp	if at end of file, write a blank line
	cpy	numChars
	blt	ee1
	lda	#' '
	jsr	SetFirst
	ldx	#0
	brl	lb3
ee1	lda	[startChar],Y	set first character
	jsr	SetFirst
	ldy	disp	if first char is a debug char then
	lda	[startChar],Y
	and	#$00FF
	cmp	breakChar
	beq	ee2	  skip it
	cmp	skipChar
	bne	dd1
ee2	inc	disp
dd1	stz	numBlanks	set up for tabs
	stz	tabIndex
	lda	left	skip chars to left of window
	beq	lb1b
	sta	leftLoop
	ldx	#0
	ldy	disp
lb1a	lda	numBlanks
	bne	bb0
	lda	[startChar],Y
	and	#$00FF
	cmp	#RETURN
	jeq	lb3
	cmp	#tab	  handle tabs during skip
	bne	bb1
	jsr	CountTabs
	iny
bb0	dey
	dec	numBlanks
bb1	iny		  increment counters for one char
	sty	disp
	inc	tabIndex
	dec	leftLoop
	bne	lb1a
lb1b	ldx	#0	set disp into line array

lb2	ldy	disp	get the next char to write
	cpy	numChars
	jge	lb3
	lda	numBlanks
	beq	cc1
	dec	disp
	dec	numBlanks
	lda	#' '
	ldy	disp
	bra	cc2
cc1	lda	[startChar],Y
	and	#$00FF
	cmp	#RETURN
	jeq	lb3
	cmp	#TAB
	bne	cc2
	jsr	CountTabs
	inc	disp
	bra	lb2
cc2	asl	a	convert to disp into character bit maps
	asl	a
	asl	a
	asl	a
	cpy	selectStart	branch if not in selection
	blt	lb2b
	cpy	selectEnd	if at end of selection, use normal
	blt	lb2a	 characters
	ldy	#$FFFF
	sty	selectStart
	bra	lb2b
lb2a	tay		place inverted char in line buffer
	lda	characters,Y
	eor	#$FFFF
	sta	line1+2,X
	lda	characters+2,Y
	eor	#$FFFF
	sta	line2+2,X
	lda	characters+4,Y
	eor	#$FFFF
	sta	line3+2,X
	lda	characters+6,Y
	eor	#$FFFF
	sta	line4+2,X
	lda	characters+8,Y
	eor	#$FFFF
	sta	line5+2,X
	lda	characters+10,Y
	eor	#$FFFF
	sta	line6+2,X
	lda	characters+12,Y
	eor	#$FFFF
	sta	line7+2,X
	lda	characters+14,Y
	eor	#$FFFF
	sta	line8+2,X
	bra	lb2c
lb2b	tay		place character in line buffer
	lda	characters,Y
	sta	line1+2,X
	lda	characters+2,Y
	sta	line2+2,X
	lda	characters+4,Y
	sta	line3+2,X
	lda	characters+6,Y
	sta	line4+2,X
	lda	characters+8,Y
	sta	line5+2,X
	lda	characters+10,Y
	sta	line6+2,X
	lda	characters+12,Y
	sta	line7+2,X
	lda	characters+14,Y
	sta	line8+2,X
lb2c	inc	disp	update disp into character table
	inx		update disp into lines
	inx
	inc	tabIndex	update tab column number
	inc	col	update column number
	lda	col
	cmp	w
	jlt	lb2
	ldy	disp	skip to eol
lb2d	lda	[startChar],Y
	and	#$00FF
	cmp	#RETURN
	beq	lb5
	iny
	sty	disp
	bne	lb2d
lb3	lda	#$FFFF	write spaces to the end of the line
	ldy	disp
	cpy	selectStart
	blt	lb3a
	cpy	selectEnd
	blt	lb3b
	sta	selectStart
	bra	lb3a
lb3b	lda	#0
lb3a	ldy	col
lb4	cpy	w
	bge	lb5
	sta	line1+2,X
	sta	line2+2,X
	sta	line3+2,X
	sta	line4+2,X
	sta	line5+2,X
	sta	line6+2,X
	sta	line7+2,X
	sta	line8+2,X
	inx
	inx
	iny
	bra	lb4
lb5	ph4	#locRec	write the character
	ph4	#rect
	lda	point+2
	and	#$0003
	pha
	ph2	yDisp
	ph2	#0
	_PPToPort
	inc	disp	next line
	add2	yDisp,#8
	inc	row
	lda	row
	cmp	h
	jlt	lb1
	brl	en1
;
;  Use the 'fast' draw
;
fs1	lda	point	multiply Y+1+lDispFromTop by 160
	sec
	adc	lDispFromTop
	ldx	#160
	jsl	~mul2
	sta	grafDisp	add in x disp div 4 + 2
	lda	point+2
	inc	a
	inc	a
	inc	a
	lsr	a
	lsr	a
	inc	a
	sec
	adc	grafDisp
	sta	grafDisp	...result is initial disp in line

	stz	disp	disp := 0;
fs2	lda	h	while h > 0 do begin
	jeq	en1
	stz	col	  col := 0;
	ldy	disp	  write first char
	cpy	numChars
	blt	ff1
	lda	#' '
	ldx	grafDisp
	jsr	SetFirstFast
	ldx	grafDisp
	brl	fs8
ff1	lda	[startChar],Y
	and	#$00FF
	cmp	breakChar
	beq	ff2
	cmp	skipChar
	bne	fs2a
ff2	inc	disp
fs2a	lda	[startChar],Y
	ldx	grafDisp
	jsr	SetFirstFast
	ldx	grafDisp	  {in case jump taken}
	ldy	disp	  y := disp;
	stz	tabIndex	  tabIndex := 0;
	stz	numBlanks	  numBlanks := 0;
	lda	left	  for x := left downto 1 do begin
	beq	fs4
	sta	leftLoop
fs3	cpy	numChars	    if y > numChars then goto 1;
	jge	fs8
	lda	numBlanks	    if numBlanks <> 0 then
	beq	fs3a
	dec	numBlanks	      numBlanks--
	bra	fs3d	      loop
fs3a	lda	[startChar],Y	    if startChar[Y] = return then
	and	#$00FF
	cmp	#return
	jeq	fs8	      goto 1;
	cmp	#tab	    if startChar[Y] = tab then
	bne	fs3c
	jsr	CountTabs	      count the spaces to insert
	dec	numBlanks	      numBlanks--
fs3c	iny		    y++;
	sty	disp	    disp++;
fs3d	inc	tabIndex	    tabIndex++;
	dec	leftLoop	    end; {for}
	bne	fs3
fs4	ldx	grafDisp	  X := grafDisp;
fs5	ldy	col	  while (startChar[disp] <> return)
	cpy	w	    and (col < w) do begin
	jeq	fs6
	lda	numBlanks	    if numBlanks <> 0 then
	beq	tb0
	dec	disp	      --disp
	dec	numBlanks	      --numBlanks
	lda	#' '	      print space
	ldy	disp
	bra	tb1
tb0	ldy	disp
	lda	[startChar],Y
	and	#$00FF
	cmp	#return
	jeq	fs8
	cpy	numChars	    if y > numChars then goto 1;
	jge	fs8
	cmp	#tab	    if startChar[disp] = tab then
	bne	tb1
	jsr	CountTabs	      count the blanks to insert
	inc	disp	      skip the tab character
	bra	fs5	      loop
tb1	asl	a	    <write char to screen>
	asl	a
	asl	a
	asl	a
	cpy	selectStart	branch if not in selection
	blt	fs5b
	cpy	selectEnd	if at end of selection, use normal
	blt	fs5a	 characters
	ldy	#$FFFF
	sty	selectStart
	bra	fs5b
fs5a	tay		place inverted char on screen
	lda	characters,Y
	eor	#$FFFF
	sta	$E12000,X
	lda	characters+2,Y
	eor	#$FFFF
	sta	$E12000+160,X
	lda	characters+4,Y
	eor	#$FFFF
	sta	$E12000+320,X
	lda	characters+6,Y
	eor	#$FFFF
	sta	$E12000+480,X
	lda	characters+8,Y
	eor	#$FFFF
	sta	$E12000+640,X
	lda	characters+10,Y
	eor	#$FFFF
	sta	$E12000+800,X
	lda	characters+12,Y
	eor	#$FFFF
	sta	$E12000+960,X
	lda	characters+14,Y
	eor	#$FFFF
	sta	$E12000+1120,X
	bra	fs5c
fs5b	tay
	lda	characters,Y
	sta	$E12000,X
	lda	characters+2,Y
	sta	$E12000+160,X
	lda	characters+4,Y
	sta	$E12000+320,X
	lda	characters+6,Y
	sta	$E12000+480,X
	lda	characters+8,Y
	sta	$E12000+640,X
	lda	characters+10,Y
	sta	$E12000+800,X
	lda	characters+12,Y
	sta	$E12000+960,X
	lda	characters+14,Y
	sta	$E12000+1120,X
fs5c	inx		    X += 2
	inx
	inc	col	    col++;
	inc	disp	    disp++
	inc	tabIndex	    tabIndex++
	brl	fs5	    end; {while}
fs6	ldy	disp	  <line ended early - skip to return>
fs6a	lda	[startChar],Y
	and	#$00FF
	cmp	#return
	beq	fs7
	cpy	numChars
	bge	fs7
	iny
	bra	fs6a
fs7	sty	disp
fs8	anop		1:
	sec		  while col < w do begin
	lda	w	    <write ' ' to screen>
	sbc	col	    ++col;
	bmi	fs10	    end; {while}
	beq	fs10
	tay
	lda	disp
	cmp	selectStart
	blt	fs8b
	cmp	selectEnd
	blt	fs8a
	lda	#$FFFF
	sta	selectStart
	bra	fs9
fs8a	lda	#0
	bra	fs9
fs8b	lda	#$FFFF
fs9	sta	$E12000,X
	sta	$E12000+160,X
	sta	$E12000+320,X
	sta	$E12000+480,X
	sta	$E12000+640,X
	sta	$E12000+800,X
	sta	$E12000+960,X
	sta	$E12000+1120,X
	inx
	inx
	dey
	bne	fs9
fs10	inc	disp	  ++disp;
	dec	h	  h := h-1;
	add2	grafDisp,#160*8	  grafDisp += 160*8;
	brl	fs2	  end; {while}
;
;  Return to the caller
;
en1	_ShowCursor
	_ObscureCursor
	ph4	port
	_SetPort
en2	return
;
;  CountTabs - count the blanks to insert for this tab
;
CountTabs anop
	phx		save caller's regs
	phy
	ldy	tabIndex
	ldx	#0
ct1	inx
	iny
	cpy	#256
	bge	ct2
	lda	[tabs],Y
	and	#$00FF
	beq	ct1
ct2	stx	numBlanks
	ply
	plx
	rts
	end

****************************************************************
*
*  DrawRuler - draw the current ruler
*
*  Inputs:
*	ruler - contains tab stops
*	infoBar - pointer to enclosing rect
*	infoData - wInfoRefCon value
*	theWindow - pointer to window
*
****************************************************************
*
DrawRuler start
	using BufferCommon
	using TabData
cn	equ	2	column number
loop	equ	4	loop counter
lineDisp equ	0	disp into the line array

	subroutine (4:infoBar,4:infoData,4:theWindow),6
	phb
	phk
	plb

	stz	lineDisp	fill in the ruler line...
	ldy	#6	set loop counter to
	lda	[infoBar],Y	 infoBar.h2 div 8 - 4
	lsr	a
	lsr	a
	lsr	a
	sec
	sbc	#4
	sta	loop
	asl	a	set the line width
	asl	a
	asl	a
	sta	rect+6
	ldy	#leftColumn	cn := leftColumn
	lda	[infoData],Y
	inc	a
	sta	cn
lb1	lda	cn	if cn mod 10 = 0 then
	ldx	#10
	jsl	~div2
	txa
	bne	lb2
	ldy	cn	  Y := cn
	bra	lb4
lb2	lda	cn	else if cn mod 5 = 0 then
	ldx	#5
	jsl	~div2
	txa
	bne	lb3
	ldy	#260	  Y := 260
	bra	lb4
lb3	ldy	#0	else Y := 0
lb4	ldx	lineDisp	place char in line
	lda	icons,Y
	sta	line1,X
	lda	icons+2,Y
	sta	line2,X
	lda	icons+4,Y
	sta	line3,X
	lda	icons+6,Y
	sta	line4,X
	lda	icons+8,Y
	sta	line5,X
	lda	cn	write the tab (or erase an old one)
	clc
	adc	#ruler
	dec	a
	tay
	lda	[infoData],Y
	and	#$00FF
	bne	lb5
	ldy	#280
	bra	lb6
lb5	ldy	#270
lb6	lda	icons,Y
	sta	line6,X
	lda	icons+2,Y
	sta	line7,X
	lda	icons+4,Y
	sta	line8,X
	inx		lineDisp += 2
	inx
	stx	lineDisp
	inc	cn	inc column #
	dbne	loop,lb1	loop

	ph4	#locRec	draw the tab line
	ph4	#rect
	ldy	#2
	lda	[infoBar],Y
	clc
	adc	#8
	pha
	lda	[infoBar]
	inc	a
	pha
	ph2	#0
	_PPToPort

	plb
	return
	end

****************************************************************
*
*  DrawTabStop - draw one tab stop
*
*  Inputs:
*	h - column number (from 0)
*	stop - tab stop
*
****************************************************************
*
DrawTabStop start
	using BufferCommon
	using TabData

	subroutine (2:h,2:stop),0

	ph4	#tr	start drawing
	ph4	currentFile+wPtr
	_StartInfoDrawing
	lda	stop	write the tab (or erase an old one)
	bne	dt1
	lda	#280+icons
	bra	dt2
dt1	lda	#270+icons
dt2	sta	iconAddr
	ph4	#iconRc	write the stuff
	ph4	#iRec
	lda	h
	inc	a
	asl	a
	asl	a
	asl	a
	inc	a
	inc	a
	pha
	ph2	#19
	ph2	#0
	_PPToPort
	_EndInfoDrawing
	return

tr	ds	8	temp rect
	end

****************************************************************
*
*  Find - Find and select a pattern
*
*  Inputs:
*	patt - pointer to the string to search for
*	whole - whole word search?
*	caseFlag - case sensitive search?
*	fold - fold whitespace?
*	flagErrors - flag an error if the string is not found?
*
****************************************************************
*
Find	start	  
	using BufferCommon
lpatt	equ	line1	use line1 for local copy of patt

TAB	equ	9	TAB key code

cp1	equ	8	work pointers for Match
cp2	equ	14
lCursor	equ	4	work copy of cursor
lengthPatt equ 12	length of the pattern
startCursor equ 0	reference cursor
			
	subroutine (4:patt,2:whole,2:caseFlag,2:fold,2:flagErrors),18
			
	stz	currentFile+verticalMove
	ldy	#254	{make a local copy of patt}
lb1	lda	[patt],Y
	sta	lpatt,Y
	dey
	dey
	bpl	lb1
!			{if not case sensitive, force uppercase}
	lda	caseFlag	if not caseFlag then
	bne	lb4
	ph4	#lpatt	  convert the string to uppercase;
	jsl	UpperCase
lb4	short I,M	{if fold whiteSpace then remove dup. spa
	lda	fold	if fold then begin
	beq	lb9
	ldx	#1	  for i := 1 to length(patt) do
	txy		    if patt[i] = chr(tab) then
lb5	lda	lpatt,X	      patt[i] := ' ';
	cmp	#TAB	  repeat
	bne	lb6	    p := pos('  ',patt);
	lda	#' '	    if p <> 0 then
	sta	lpatt,X	      delete(patt,p,1);
lb6	cmp	#' '	  until p = 0;
	bne	lb8
	sta	lpatt,Y
lb7	lda	lpatt+1,X
	cmp	#' '
	bne	lb8
	inx
	bra	lb7
lb8	lda	lpatt,X
	sta	lpatt,Y
	inx
	iny
	cpx	lpatt
	ble	lb5
	dey
	sty	lpatt
lb9	long	I,M	  end; {if}
!			with currentFile do begin
!			  {remove any selection}
	stz	currentFile+selection	  selection := false;
!			  {mark the current position}
	move4 currentFile+cursor,startCursor startCursor := cursor;
	move4 startCursor,lCursor	  {work copy}
lc1	anop		  repeat
!			    {increment the cursor}
	inc4	lcursor	    cursor := pointer(ord4(cursor)+1);
	cmpl	lcursor,currentFile+buffEnd  if cursor = buffEnd then begin
	bne	lc3
	move4 currentFile+buffStart,lcursor  cursor := buffStart;
lc3	anop		      end; {if}
	cmpl	lcursor,currentFile+gapStart if cursor = gapStart then
	bne	lc4
	move4 currentFile+pageStart,lcursor  cursor := pageStart;
lc4	anop		    {check for complete loop thru file}
	cmpl	lcursor,startCursor	    if cursor = startCursor then begin
	bne	lc5
	jsr	Match	      done := Match;
	bcs	lc5a	      if not done then begin
	lda	oldSelection		selection := oldSelection;
	sta	currentFile+selection
	move4 startCursor,currentFile+cursor	cursor := startCursor;
	jsl	FindCursor		FindCursor;
	jsl	FollowCursor		FollowCursor;
	ph4	currentFile+wPtr		StartDrawing(wPtr);
	_StartDrawing
	jsl	DrawScreen		DrawScreen;
	lda	flagErrors		if flagErrors then
	beq	lc7
	ph2	#10		  FlagError(10, 0);
	ph2	#0
	jsl	FlagError
	bra	lc7		done := true;
!				end; {if}
!			      end {if}
lc5	anop		    else begin
!			      {see if we have a match}
	jsr	Match	      done := Match;
	jcc	lc1	      if done then begin
lc5a	move4 lcursor,currentFile+cursor	FindCursor;
	jsl	FindCursor
	jsl	FollowCursor		FollowCursor;
	ph4	currentFile+wPtr		StartDrawing(wPtr);
	_StartDrawing
	jsl	DrawScreen		DrawScreen;
!				end; {if}
!			      end; {else}
!			  until done;
!			  end; {with}
lc7	return 	end; {Find}
;
;  Match - see if the current string matches the target string
;
;  Returns C=1 if the strings match, C=0 if not
;
Match	anop	                       
!			with currentFile do begin
!			  {assume no match}
!			  Match := false;
!			  {check for whitespace before whole word}
	lda	whole	  if whole then begin
	beq	mc1
	sub4	lcursor,#1,cp1	    cp1 := pointer(ord4(cursor)-1);
	lda	[cp1]	    if AlphaNumeric(chr(cp1^))
	jsr	AlphaNumeric	      and (cursor <> buffStart)
	bcc	mc1	      and (cursor <> pageStart) then
	cmpl	lcursor,currentFile+buffStart
	beq	mc1
	cmpl	lcursor,currentFile+pageStart
	beq	mc1
	clc		      goto 1;
	rts
mc1	anop		    end; {if}
!			  {scan for match}
	move4 lcursor,cp1	  cp1 := cursor;
	lda	lpatt	  for i := 1 to length(patt) do begin
	and	#$00FF
	sta	lengthPatt
	ldx	#1
mc2	lda	[cp1]	    ch := cp1^;
	and	#$00FF
	ldy	caseFlag	    if not caseFlag then
	bne	mc3
	cmp	#'a'	      if (ch >= ord('a')) and (ch <= ord('z')) then
	blt	mc3
	cmp	#'z'+1
	bge	mc3
	and	#$005F		ch := ch & $5F;
mc3	ldy	fold	    if fold then
	beq	mc3a
	cmp	#tab	      if ch = tab then
	bne	mc3a
	lda	#' '		ch := ' ';
mc3a	short M	    if ch <> ord(patt[i]) then
	cmp	lpatt,X
	long	M
	beq	mc4	      goto 1;
	clc
	rts
mc4	ldy	fold	    if fold then
	beq	mc7
mc5	anop		      repeat
	move4 cp1,cp2		cp2 := cp1;
	inc4	cp1		cp1 := pointer(ord4(cp1)+1);
	lda	[cp2]	      until not (cp2^ in [space,tab]) or not (cp1^ in [space,tab])
	and	#$00FF
	cmp	#' '
	beq	mc6
	cmp	#TAB
	bne	mc8
mc6	lda	[cp1]
	and	#$00FF
	cmp	#' '
	beq	mc5
	cmp	#TAB
	beq	mc5
	bra	mc8	    else
mc7	inc4	cp1	      cp1 := pointer(ord4(cp1)+1);
mc8	inx		    end; {for}
	cpx	lengthPatt
	ble	mc2
!			  {check for whitespace after whole word}
	lda	whole	  if whole then begin
	beq	mc9
	lda	[cp1]	    if AlphaNumeric(chr(cp1^))
	jsr	AlphaNumeric
	bcc	mc9
	cmpl	cp1,currentFile+buffEnd	      and (cp1 <> buffEnd)
	beq	mc9
	cmpl	cp1,currentFile+gapStart	      and (cp1 <> gapStart) then
	beq	mc9
	clc		      goto 1;
	rts
mc9	anop		    end; {if}
!			  {match found - select the text}
	lda	#1	  selection := true;
	sta	currentFile+selection
	move4 cp1,currentFile+select	  select := cp1;
	sec		  Match := true;
	rts		  end; {with}
!			1:
;
;  AlphaNumeric - see if a character is alphanumeric.  If so,
;  return with C=1, else return with C=0.
;
AlphaNumeric anop
	short M
	cmp	#'a'
	blt	an1
	cmp	#'z'+1
	blt	yes
an1	cmp	#'A'
	blt	an2
	cmp	#'Z'+1
	blt	yes
an2	cmp	#'0'
	blt	an3
	cmp	#'9'+1
	blt	yes
an3	long	M
	clc
	rts

yes	long	M
	sec
	rts
	end		

****************************************************************
*
*  FindCursor - find the cursor row and column based on its position
*
****************************************************************
*
FindCursor start
	using BufferCommon

cp	equ	1	work pointer

	phd		<set up a work pointer>
	pha
	pha
	tsc
	tcd
!			with currentFile do begin
	stz	currentFile+verticalMove   verticalMove := false;
	stz	currentFile+cursorRow	  cursorRow := 0;
	stz	currentFile+cursorRow+2
!			  if ord4(cursor) < ord4(pageStart) then begin
	cmpl	currentFile+cursor,currentFile+pageStart
	bge	lb3
	move4 currentFile+gapStart,cp	    cp := gapStart;
lb1	anop		    repeat
	dec4	cp	      cp := pointer(ord4(cp)-1);
	lda	[cp]	      if cp^ = return then
	and	#$00FF
	cmp	#RETURN
	bne	lb2
	dec4	currentFile+cursorRow		cursorRow := cursorRow-1;
lb2	cmpl	cp,currentFile+cursor	    until cp = cursor;
	bne	lb1
	bra	lb7	    end {if}
lb3	anop		  else begin
	move4 currentFile+pageStart,cp	    cp := pageStart;
lb4	cmpl	cp,currentFile+cursor	    while cp <> cursor do begin
	beq	lb7
	lda	[cp]	      if cp^ = return then
	and	#$00FF
	cmp	#RETURN
	bne	lb5
	inc4	currentFile+cursorRow		cursorRow := cursorRow+1;
lb5	inc4	cp	      cp := pointer(ord4(cp)+1);
	bra	lb4	      end; {while}
lb7	anop		    end; {else}
	jsl	FindCursorColumn	  cursorColumn := FindCursorColumn;
	sta	currentFile+cursorColumn	  end; {with}
	pla		<fix stack & return>
	pla
	pld
	rtl
	end

****************************************************************
*
*  InsertChar - insert a character in the buffer
*
*  Outputs:
*	InsertChar - true if the insert was successful
*
****************************************************************
*
InsertChar private
	using BufferCommon

	subroutine ,0

	stz	fnResult
!			with currentFile do begin
!			  {if we need more room, get it}
	lda	currentFile+gapStart	  if gapStart = pageStart then
	cmp	currentFile+pageStart
	bne	lb1
	lda	currentFile+gapStart+2
	cmp	currentFile+pageStart+2
	bne	lb1
	jsl	GrowBuffer	    GrowBuffer;
	lda	currentFile+gapStart	  if gapStart <> pageStart then begin
	cmp	currentFile+pageStart
	bne	lb1
	lda	currentFile+gapStart+2
	cmp	currentFile+pageStart+2
	beq	lb2
lb1	ph4	#1	    Undo_Insert(1);
	jsl	Undo_Insert
	ph4	currentFile+pageStart	    MoveBack(pageStart,
	sec		      pointer(ord4(pageStart)-1),
	lda	currentFile+pageStart	      ord4(cursor)-ord4(pageStart));
	sbc	#1
	tax
	lda	currentFile+pageStart+2
	sbc	#0
	pha
	phx
	sec
	lda	currentFile+cursor
	sbc	currentFile+pageStart
	tax
	lda	currentFile+cursor+2
	sbc	currentFile+pageStart+2
	pha
	phx
	jsl	MoveBack
	dec4	currentFile+pageStart	    pageStart :=
!			      pointer(ord4(pageStart)-1);
	lda	#1	    {note success}
	sta	fnResult	    InsertChar := true;
!			    {the file has changed}
	sta	currentFile+changed	    changed := true;
	sta	currentFile+changesSinceCompile changesSinceCompile := true;
	bra	lb3	    end {if}
lb2	anop		  else
!			    {no room for it}
	jsl	OutOfMemory	   InsertChar := false;
lb3	anop		  end; {with}
	return 2:fnResult

fnResult ds	2
	end

****************************************************************
*
*  MoveBack - move a block of memory to a lower address
*
*  Inputs:
*	sp - source pointer
*	dp - destination pointer
*	size - # of bytes to move
*
****************************************************************
*
MoveBack start

	subroutine (4:sp,4:dp,4:size),0

	lda	size+2	move 64K blocks
	beq	lb2
	ldy	#0
lb1	lda	[sp],Y
	sta	[dp],Y
	iny
	iny
	bne	lb1
	inc	sp+2
	inc	dp+2
	dbne	size+2,lb1
lb2	lda	size	quit if no more bytes to move
	beq	lb5
	lsr	a	if there are an odd number of bytes,
	tax		 move one byte
	bcc	lb3
	short M
	lda	[sp]
	sta	[dp]
	long	M
	txa
	beq	lb5
	inc4	sp
	inc4	dp
lb3	ldy	#0	move remaining words
lb4	lda	[sp],Y
	sta	[dp],Y
	iny
	iny
	dbne	X,lb4
lb5	return
	end

****************************************************************
*
*  MoveForward - move a block of memory to a higher address
*
*  Inputs:
*	sp - source pointer+1
*	dp - destination pointer+1
*	size - # of bytes to move
*
****************************************************************
*
MoveForward start

	subroutine (4:sp,4:dp,4:size),0

	lda	size+2	move 64K blocks
	beq	lb3
lb1	ldy	#$FFFE
	dec	sp+2
	dec	dp+2
lb2	lda	[sp],Y
	sta	[dp],Y
	dey
	dey
	bne	lb2
	lda	[sp]
	sta	[dp]
	dbne	size+2,lb1
lb3	lda	size	quit if no more bytes to move
	beq	lb9
	lsr	a	if there are an odd number of bytes,
	tax		 move one byte
	bcc	lb4
	dec4	sp
	dec4	dp
	short M
	lda	[sp]
	sta	[dp]
	long	M
	txa		move remaining words
	beq	lb9
lb4	asl	a
	sta	size+2
	sec
	lda	sp
	sbc	size+2
	sta	sp
	bcs	lb5
	dec	sp+2
lb5	sec
	lda	dp
	sbc	size+2
	sta	dp
	bcs	lb6
	dec	dp+2
lb6	ldy	size+2
	dey
	dey
	beq	lb8
lb7	lda	[sp],Y
	sta	[dp],Y
	dey
	dey
	bne	lb7
lb8	lda	[sp]
	sta	[dp]
lb9	return
	end

****************************************************************
*
*  MoveToStart - move the cursor to the start of the current line
*
****************************************************************
*
MoveToStart start
	using BufferCommon

lcursor	equ	1	local copy of cursor
min	equ	5	minimum allowed value for cursor

	phd		create the work space
	tsc
	sec
	sbc	#8
	tcs
	tcd

	stz	currentFile+verticalMove
	move4 currentFile+cursor,lcursor with currentFile do begin
	cmpl	lcursor,currentFile+gapStart if ord4(cursor) < ord4(gapStart) then
	bge	lb1
	move4 currentFile+buffStart,min     min := buffStart
	bra	lb2	   else
lb1	move4 currentFile+pageStart,min     min := pageStart;
lb2	cmpl	lcursor,min	   if cursor <> min then begin
	beq	lb6
	bra	lb4	     cursor := pointer(ord4(cursor)-1);
lb3	cmpl	lcursor,min	     while (cursor <> min) and (cursor^ <> return) do
	beq	lb5
	lda	[lcursor]
	and	#$00FF
	cmp	#RETURN
	beq	lb5
lb4	dec4	lcursor	       cursor := pointer(ord4(cursor)-1);
	bra	lb3
lb5	lda	[lcursor]	     if cursor^ = return then
	and	#$00FF
	cmp	#RETURN
	bne	lb6
	inc4	lcursor	       cursor := pointer(ord4(cursor)+1);
lb6	anop		     end; {if}
	move4 lcursor,currentFile+cursor  end; {with}

	pla
	pla
	pla
	pla
	pld
	rtl
	end

****************************************************************
*
*  NewWindowFrame - create a new window frame
*
*  Inputs:
*	xLoc,yLoc - location of the window
*	dataW,dataH - size of data area
*	plane - window plane
*	infoBar - is there an information bar?
*	title - initial window name
*
****************************************************************
*
NewWindowFrame start
infoHeight equ 12	height of the information bar

	subroutine (2:xLoc,2:yLoc,2:dataW,2:dataH,4:plane,2:infoBar,4:title),0

	lda	infoBar	set window frame based on info bar
	beq	lb1
	lda	#$C1B6
	bra	lb2
lb1	lda	#$C1A6
lb2	sta	wFrame
	move4 title,wTitle	set window title
	lda	infoBar	set zoom height based on info bar
	beq	lb3
	lda	#25+infoHeight
	bra	lb4
lb3	lda	#25
lb4	sta	wZoom
	lda	dataH	set data size
	sta	wDataH
	lda	dataW
	sta	wDataW
	lda	yLoc	set initial position
	clc
	adc	#25
	sta	wPosition
	clc
	adc	dataH
	sta	wPosition+4
	lda	xLoc
	sta	wPosition+2
	clc
	adc	dataW
	sta	wPosition+6
	move4 plane,wPlane	set window plane
	pha		create the window
	pha
	ph4	#myWindowDef
	_NewWindow
	pl4	nwPtr
	return 4:nwPtr

nwPtr	ds	4	new window pointer

myWindowDef anop
	dc	i'78'	length of the record
wFrame	ds	2	window frame bits
wTitle	ds	4	pointer to window's title
	dc	i4'0'	window reference constant
wZoom	dc	i'25,0,200,640'	zoomed window size
	dc	a4'colors'	window color table pointer
	dc	i'0,0'	window origin
wDataH	ds	2	window height
wDataW	ds	2	window width
	dc	i'175,640'	max height, width
	dc	i'0,0'	# pixels to scroll for arrows
	dc	i'0,0'	# pixels to scroll for page move
	dc	i4'0'	info bar reference constant
	dc	i'infoHeight'	height of the info bar
	dc	3a4'0'	window frame, info bar, content def proc
wPosition ds	8	window position
wPlane	ds	4	window plane
	dc	a4'0'	window record storage

colors	dc	i'$0000'
	dc	i'$0F00'
	dc	i'$020F'
	dc	i'$0000'
	dc	i'$00F0'
	end

****************************************************************
*
*  OnScreen - see if the current port is entirely on the screen
*
*  Outputs:
*	C - set if on screem, else clear
*
*  Notes:
*	called with JSR
*
****************************************************************
*
OnScreen private

	ph4	#rect
	_GetPortRect
	ph4	#rect
	_LocalToGlobal
	ph4	#rect+4
	_LocalToGlobal
	lda	rect
	ora	rect+2
	bmi	no
	lda	rect+4
	cmp	#201
	bge	no
	lda	rect+6
	cmp	#641
	bge	no
	sec
	rts

no	clc
	rts

rect	ds	8
	end

****************************************************************
*
*  DoPaste - paste the scrap into the current file at the cursor location
*
*  Inputs:
*	useScrap - use the scrap? (or use rPattPtr)
*	rPattPtr - pointer to the chars to paste
*	len - length of the characters to paste
*
*  Notes:
*	The characters to paste can come from two locations.
*	If useScrap = true, the characters are taken from the
*	scrap manager.  If useScrap = false, rPattPtr must
*	point to the first character in a contiguous buffer
*	of characters, and len indicates how many characters
*	are in the buffer.
*
****************************************************************
*
DoPaste	start
	using BufferCommon

	subroutine (2:useScrap,4:rPattPtr,2:len),24

cp1	equ	rPattPtr	use rPattPtr for work pointer
gapSize	equ	8	size of the gap in the edit buffer
lastSize equ	4	free memory in edit buffer
lcursor	equ	20	work copy cursor
oldNumLines equ 16	original value for numLines
scrapHandle equ 12	work handle for finding the scrap
size	equ	0	size of the scrap

	_WaitCursor	WaitCursor; {this takes time...}
!			{get the cursor on the screen}
	stz	currentFile+verticalMove
	jsl	FollowCursor	FollowCursor;
!			{find the size}
	lda	useScrap	if useScrap then
	beq	lb1
	pha		  size := GetScrapSize(text)
	pha
	ph2	#0
	_GetScrapSize
	pl4	size
	jcs	ld3
	bra	lb2
lb1	anop		else
	lda	len	  size := len;
	sta	size
	stz	size+2
lb2	lda	size	if size <> 0 then
	ora	size+2
	jeq	ld3
	anop		  with currentFile do begin
!			    {delete selected text}
	jsl	DeleteSelection	    DeleteSelection;
!			    {place trailing blanks on the line}
	jsl	BlankExtend	    BlankExtend;
	ph4	size	    {mark for later undo}
	jsl	Undo_Insert	    Undo_Insert(size);
!			    {make room in the buffer}
	lda	#$FFFF	    lastSize := -1;
	sta	lastSize
	sta	lastSize+2
!			    gapSize := ord4(pageStart)-ord4(gapStart);
	bra	lb6
lb4	lda	gapSize	    while (gapSize <> lastSize) and
	ldx	gapSize+2	      (gapSize < size) do begin
	cmp	lastSize
	bne	lb5
	cpx	lastSize+2
	beq	lb7
lb5	cpx	size+2
	bne	lb5b
	cmp	size
lb5b	bge	lb7
	sta	lastSize	      lastSize := gapSize;
	stx	lastSize+2
	jsl	GrowBuffer	      GrowBuffer;
!			      gapSize := ord4(pageStart)-ord4(gapStart);
lb6	sub4	currentFile+pageStart,currentFile+gapStart,gapSize
	bra	lb4	      end; {while}
lb7	cmpl	gapSize,size	    if gapSize >= size then begin
	jlt	ld3	      {make room at the insertion point}
	ph4	currentFile+pageStart	      MoveBack(pageStart,
	sec			pointer(ord4(pageStart)-size),
	lda	currentFile+pageStart
	sbc	size
	tax
	lda	currentFile+pageStart+2
	sbc	size+2
	pha
	phx
	sec			ord4(cursor)-ord4(pageStart));
	lda	currentFile+cursor
	sbc	currentFile+pageStart
	tax
	lda	currentFile+cursor+2
	sbc	currentFile+pageStart+2
	pha
	phx
	jsl	MoveBack
ld7a	sub4	currentFile+pageStart,size     pageStart := pointer(ord4(pageStart)-size);
	sub4	currentFile+cursor,size	      cursor := pointer(ord4(cursor)-size);
!			      {set up pointer to chars to copy}
	lda	useScrap	      if useScrap then begin
	beq	lc1
	pha			scrapHandle := GetScrapHandle(text);
	pha
	ph2	#0
	_GetScrapHandle
	pl4	scrapHandle
	ph4	scrapHandle		HLock(scrapHandle);
	_HLock
	ldy	#2		cp1 := scrapHandle^;
	lda	[scrapHandle]
	sta	cp1
	lda	[scrapHandle],Y
	sta	cp1+2
!				end {if}
!			      else
!				cp1 := pointer(rPattPtr);
lc1	move4 currentFile+numLines,oldNumLines oldNumLines := numLines;
!			      {copy in the characters}
	move4 currentFile+cursor,lcursor     <<<check the bytes>>>
	short M
	ldx	size+2	      {check 64K chunks}
	beq	mm5
mm1	ldy	#0
mm2	lda	[cp1],Y
	and	#$FF
	cmp	#RETURN
	bne	mm3
	inc4	currentFile+numLines
	bra	mm4
mm3	cmp	#' '
	bge	mm4
	cmp	#tab
	beq	mm4
	cmp	#$11
	blt	mm3a
	cmp	#$15
	blt	mm4
mm3a	lda	#' '
mm4	sta	[lcursor],Y
	dey
	bne	mm2
	inc	cp1+2
	inc	cursor+2
	dex
	bne	mm1
mm5	ldy	size	      {check last chunk}
	beq	mm12
	dey
	beq	mm9
mm6	lda	[cp1],Y
	and	#$FF
	cmp	#RETURN
	bne	mm7
	inc4	currentFile+numLines
	bra	mm8
mm7	cmp	#' '
	bge	mm8
	cmp	#tab
	beq	mm8
	cmp	#$11
	blt	mm7a
	cmp	#$15
	blt	mm8
mm7a	lda	#' '
mm8	sta	[lcursor],Y
	dey
	bne	mm6
mm9	lda	[cp1]
	and	#$FF
	cmp	#RETURN
	bne	mm10
	inc4	currentFile+numLines
	bra	mm11
mm10	cmp	#' '
	bge	mm11
	cmp	#tab
	beq	mm11
	cmp	#$11
	blt	mm10a
	cmp	#$15
	blt	mm11
mm10a	lda	#' '
mm11	sta	[lcursor]
mm12	long	M
	clc
	lda	size
	adc	lcursor
	sta	currentFile+cursor
	lda	#0
	adc	lcursor+2
	sta	currentFile+cursor+2
lc6	anop		      {repair cursor variables}
	jsl	FindCursor	      FindCursor;
!			      {check for last line too long}
	jsl	Check255	      Check255;
!			      {adjust controls}
	cmpl	currentFile+numLines,oldNumLines if numLines <> oldNumLines then begin
	beq	lc11
	clc			SetCtlParams(max2(numLines+height),height,vScroll);
	lda	currentFile+numLines
	adc	currentFile+height
	bcs	lc7
	ldx	currentFile+numLines+2
	beq	lc8
lc7	lda	#$FFFF
lc8	pha
	ph2	currentFile+height
	ph4	currentFile+vScroll
	_SetCtlParams
	lda	currentFile+splitScreen		if splitScreen then
	beq	lc11
	clc			  SetCtlParams(max2(numLines+heightAlt),heightAlt,vScrollAlt);
	lda	currentFile+numLines
	adc	currentFile+heightAlt
	bcs	lc9
	ldx	currentFile+numLines+2
	beq	lc10
lc9	lda	#$FFFF
lc10	pha
	ph2	currentFile+heightAlt
	ph4	currentFile+vScrollAlt
	_SetCtlParams
lc11	anop			end; {if}
	lda	currentFile+splitScreen	      if splitScreen then
	beq	ld1
!				if topLineAlt > topLine+cursorRow then
	add4	currentFile+topLine,currentFile+cursorRow,lcursor
	cmpl	currentFile+topLineAlt,lcursor
	ble	ld1
!				  topLineAlt := topLineAlt+numLines-oldNumLines;
	sub4	currentFile+numLines,oldNumLines,lcursor
	add4	currentFile+topLineAlt,lcursor
ld1	anop		      {unlock the scrap}
	lda	useScrap	      if useScrap then
	beq	ld2
	ph4	scrapHandle		HUnLock(scrapHandle);
	_HUnLock
ld2	anop		      {make sure we're on screen}
	jsl	FollowCursor	      FollowCursor;
!			      {the file has changed}
	lda	#1	      changed := true;
	sta	currentFile+changed
	sta	currentFile+changesSinceCompile changesSinceCompile := true;
ld3	anop		      end; {if}
!			    end; {with}
	jsl	ResetCursor	ResetCursor;
	return 	end; {DoPaste}
	end

****************************************************************
*
*  ScanForward - starting at sp, move forward lines lines
*
*  Inputs:
*	sp - starting pointer
*	lines - number of lines to move
*
*  Outputs:
*	X-A - pointer to start of new line
*
****************************************************************
*
ScanForward private
	using BufferCommon

sp	equ	8	starting pointer
lines	equ	4	# lines to move

	tsc
	phd
	tcd

lb1	lda	lines	quit if at the proper line
	ora	lines+2
	beq	lb4
	ldy	#-1	scan to the end of this line
	short M
	lda	#RETURN
lb2	iny
	cmp	[sp],Y
	bne	lb2
	long	M
	sec		add the length of the line to sp
	tya
	adc	sp
	sta	sp
	bcc	lb3
	inc	sp+2
lb3	dec4	lines	next line
	bra	lb1
lb4	ldx	sp+2	return
	ldy	sp
	pld
	php
	pla
	sta	7,S
	pla
	sta	7,S
	pla
	pla
	plp
	tya
	rtl
	end

****************************************************************
*
*  ScrollDown - Move towards the end of the file
*
*  Inputs:
*	lines - number of lines to scroll
*
****************************************************************
*
ScrollDown start
	using BufferCommon

checkCursor equ 4	do we need to check the cursor?
checkSelect equ 6	do we need to check select?
gapSize	equ	8	size of the file gap
oldTopLine equ 0	original value of topLine
size	equ	12	size of the block to move
t	equ	8	temp result - overlaps gapSize

cf	equ	currentFile	currentFile variable

	subroutine (4:lines),16

	move4 cf+topLine,oldTopLine	save topLine for later checks
	cmpl	cf+numLines,cf+topLine	if (numLines <> topLine) and
	jeq	lb9	  (lines <> 0) then begin
	lda	lines
	ora	lines+2
	jeq	lb9
	stz	checkCursor	  checkCursor := cursor >= pageStart;
	cmpl	cf+cursor,cf+pageStart
	blt	lb1
	inc	checkCursor
lb1	stz	checkSelect	  checkSelect := select >= pageStart;
	cmpl	cf+select,cf+pageStart
	blt	lb2
	inc	checkSelect
lb2	sub4	cf+numLines,cf+topLine,t	  if lines >= numLines-topLine then begin
	cmpl	lines,t
	blt	lb2a
	move4 t,lines	    lines := numLines-topLine;
	sub4	cf+buffEnd,cf+pageStart,size size := buffEnd-pageStart;
	bra	lb6	    end {if}
lb2a	anop		  else begin
	move4 cf+pageStart,size	    size := pageStart;
	lda	lines+2	    for i := 1 to lines do begin
	sta	t
	ldx	lines
lb3	ldy	#-1	      while size^ <> RETURN do
	short M		++size;
	lda	#RETURN	      ++size;
lb4	iny
	cmp	[size],Y
	bne	lb4
	long	M
	tya
	sec
	adc	size
	sta	size
	bcc	lb5
	inc	size+2
lb5	dex		      end; {for}
	bne	lb3
	dec	t
	bpl	lb3
	sub4	size,cf+pageStart	    size := size-pageStart;
lb6	anop		    end; {else}
	ph4	cf+pageStart	  MoveBack(pageStart,gapStart,size);
	ph4	cf+gapStart
	ph4	size
	jsl	MoveBack
	sub4	cf+cursorRow,lines	  cursorRow -= lines;
	add4	cf+topLine,lines	  topLine += lines;
	add4	cf+gapStart,size	  gapStart += size;
	add4	cf+pageStart,size	  pageStart += size;
	sub4	cf+pageStart,cf+gapStart,gapSize gapSize := pageStart-gapStart;
	lda	checkCursor	  if checkCursor then
	beq	lb7
	cmpl	cf+cursor,cf+pageStart	    if cursor < pageStart then
	bge	lb7
	sub4	cf+cursor,gapSize	      cursor -= gapSize;
lb7	lda	checkSelect	  if checkSelect then
	beq	lb8
	cmpl	cf+select,cf+pageStart	    if select < pageStart then
	bge	lb8
	sub4	cf+select,gapSize	      select -= gapSize;
lb8	anop		  end; {if}

	jsr	~ScrollCheck	if screen moved, update it
lb9	return
;
;  ~ScrollCheck - repair screen if it moved
;
;  Note: subroutines that call this one must place oldTopLines in DP
;  location 0.
;
~ScrollCheck entry
	lda	currentFile+topLine	if (topLine <> oldTopLine)
	cmp	oldTopLine	 or splitScren then update screen
	bne	sc1
	lda	currentFile+topLine+2
	cmp	oldTopLine+2
	bne	sc1
	lda	currentFile+splitScreen
	beq	sc4
sc1	jsl	DrawScreen
	lda	currentFile+topLine+2
	beq	sc2
	lda	#$FFFF
	bra	sc3
sc2	lda	currentFile+topLine
sc3	pha
	ph4	currentFile+vScroll
	_SetCtlValue
sc4	rts
	end

****************************************************************
*
*  ScrollUp - Move towards the beginning of the file
*
*  Inputs:
*	lines - number of lines to scroll
*
****************************************************************
*
ScrollUp start
	using BufferCommon

checkCursor equ 4	do we need to check the cursor?
checkSelect equ 6	do we need to check select?
gapSize	equ	8	size of the file gap
oldTopLine equ 0	original value of topLine
size	equ	12	size of the block to move

cf	equ	currentFile	currentFile variable

	subroutine (4:lines),16

	move4 cf+topLine,oldTopLine	save topLine for later checks
	lda	lines	quit if there is nothing needed
	ora	lines+2
	jeq	lb8
	stz	checkCursor	checkCursor := cursor < gapStart;
	cmpl	cf+cursor,cf+gapStart
	bge	lb1
	inc	checkCursor
lb1	stz	checkSelect	checkSelect := select < gapStart;
	cmpl	cf+select,cf+gapStart
	bge	lb2
	inc	checkSelect
lb2	sub4	cf+pageStart,cf+gapStart,gapSize gapSize := pageStart-gapStart;
	cmpl	lines,cf+topLine	if lines >= topLine then begin
	blt	lb3
	move4 cf+topLine,lines	  lines := topLine;
	sub4	cf+gapStart,cf+buffStart,size size := gapStart-buffStart;
	bra	lb5	  end {if}
lb3	anop		else begin
	sub4	cf+gapStart,#1,size	  size := gapStart-1;
	ldx	lines	  for i := 1 to lines do
	ldy	lines+2
lb4	anop		    repeat
	dec4	size	      size--
	lda	[size]	    until size^ = RETURN;
	and	#$00FF
	cmp	#RETURN
	bne	lb4
	dex
	bne	lb4
	dey
	bpl	lb4
	clc		  size := gapStart-size-1;
	lda	cf+gapStart
	sbc	size
	sta	size
	lda	cf+gapStart+2
	sbc	size+2
	sta	size+2
lb5	anop		  end; {else}
	ph4	cf+gapStart	MoveForward(gapStart,pageSize,size);
	ph4	cf+pageStart
	ph4	size
	jsl	MoveForward
	add4	cf+cursorRow,lines	cursorRow += lines;
	sub4	cf+topLine,lines	topLine -= lines;
	sub4	cf+gapStart,size	gapStart -= size;
	sub4	cf+pageStart,size	pageStart -= size;
	lda	checkCursor	if checkCursor then
	beq	lb6
	cmpl	cf+cursor,cf+gapStart	  if cursor >= gapStart then
	blt	lb6
	add4	cf+cursor,gapSize	    cursor += gapSize;
lb6	lda	checkSelect	if checkSelect then
	beq	lb7
	cmpl	cf+select,cf+gapStart	  if select >= gapStart then
	blt	lb7
	add4	cf+select,gapSize	    select += gapSize;
lb7	jsr	~ScrollCheck	if screen moved, update it
lb8	return
	end

****************************************************************
*
*  SetCharacters - set the auto-go and breakpoint characters
*
*  Inputs:
*	currentFile+newDebug - use new or old characters?
*	breakChar - used to decide if the character bitmap
*		should be changed
*
*  Outputs:
*	breakChar - set appropriately
*	skipChar - set appropriately
*	character bitmaps - set appropriately
*
****************************************************************
*
SetCharacters private
	using	BufferCommon

	lda	currentFile+newDebug	decide which character to use
	beq	old

	lda	#newBreakChar	if this is not a change then
	cmp	breakChar
	beq	rts	  return
	jsr	SwapCharacters	swap the debug characters
	lda	#newBreakChar	breakChar := newBreakChar
	sta	breakChar
	lda	#newSkipChar	skipChar := newSkipChar
	sta	skipChar
rts	rts		return

old	lda	#oldBreakChar	if this is not a change then
	cmp	breakChar
	beq	rts	  return
	jsr	SwapCharacters	swap the debug characters
	lda	#oldBreakChar	breakChar := oldBreakChar
	sta	breakChar
	lda	#oldSkipChar	skipChar := oldSkipChar
	sta	skipChar
	rts		return

SwapCharacters anop	swap the debug characters
	ldx	#14
sc1	lda	Characters+oldBreakChar*16,X
	tay
	lda	Characters+newBreakChar*16,X
	sta	Characters+oldBreakChar*16,X
	tya
	sta	Characters+newBreakChar*16,X
	lda	Characters+oldSkipChar*16,X
	tay
	lda	Characters+newSkipChar*16,X
	sta	Characters+oldSkipChar*16,X
	tya
	sta	Characters+newSkipChar*16,X
	dex
	dex
	bpl	sc1
	rts
	end

****************************************************************
*
*  SetFirst - set the first char for quickdraw
*
*  Inputs:
*	A - character to use for 1st col
*
****************************************************************
*
SetFirst private
	using BufferCommon

	and	#$00FF	use space if not a special char
	cmp	breakChar
	beq	lb1
	cmp	skipChar
	beq	lb1
	lda	#' '
lb1	asl	a	convert to disp into characters array
	asl	a
	asl	a
	asl	a
	tay		place character in line buffer
	lda	characters,Y
	sta	line1
	lda	characters+2,Y
	sta	line2
	lda	characters+4,Y
	sta	line3
	lda	characters+6,Y
	sta	line4
	lda	characters+8,Y
	sta	line5
	lda	characters+10,Y
	sta	line6
	lda	characters+12,Y
	sta	line7
	lda	characters+14,Y
	sta	line8
	rts
	end

****************************************************************
*
*  SetFirstFast - set the first char for fast draw
*
*  Inputs:
*	A - character to use for 1st col
*	X - disp into screen + 2
*
****************************************************************
*
SetFirstFast private
	using BufferCommon

	and	#$00FF	use space if not a special char
	cmp	breakChar
	beq	lb1
	cmp	skipChar
	beq	lb1
	lda	#' '
lb1	asl	a	convert to disp into characters array
	asl	a
	asl	a
	asl	a
	tay		place character in line buffer
	lda	characters,Y
	sta	$E12000-2,X
	lda	characters+2,Y
	sta	$E12000+160-2,X
	lda	characters+4,Y
	sta	$E12000+320-2,X
	lda	characters+6,Y
	sta	$E12000+480-2,X
	lda	characters+8,Y
	sta	$E12000+640-2,X
	lda	characters+10,Y
	sta	$E12000+800-2,X
	lda	characters+12,Y
	sta	$E12000+960-2,X
	lda	characters+14,Y
	sta	$E12000+1120-2,X
	rts
	end

****************************************************************
*
*  SetSelection - Set the displacements to selected text
*
*  Inputs:
*	selection - is there a selection?
*	select - one end of selected area
*	cursor - other end of selected area
*	startPtr - ptr to first char to be drawn
*
*  Outputs:
*	selectStart - disp to first selection; $FFFF if none on screen
*	selectEnd - disp to last selection
*
****************************************************************
*
SetSelection private
	using BufferCommon

selectStart equ 0	start disp of selected text
selectEnd equ	4	end disp of selected text
startPtr equ	8	ptr to first char to be drawn

	lda	currentFile+selection	convert cursor, select to disps past
	beq	sl6	 the start of the page
	lda	currentFile+select+2
	cmp	currentFile+cursor+2
	bne	sl1
	lda	currentFile+select
	cmp	currentFile+cursor
sl1	blt	sl2
	sub4	currentFile+cursor,startPtr,selectStart
	sub4	currentFile+select,startPtr,selectEnd
	bra	sl3
sl2	sub4	currentFile+select,startPtr,selectStart
	sub4	currentFile+cursor,startPtr,selectEnd
sl3	lda	selectEnd+2	not on page if selection end is
	bmi	sl6	 before the start of the page
	lda	selectStart+2	if selectEnd < 0 then start disp is 0
	bpl	sl4
	stz	selectStart
sl4	lda	selectEnd+2	if selecrEnd > 65535 then end disp is
	beq	sl5	  65535
	lda	#$FFFF
	sta	selectEnd
sl5	rts

sl6	lda	#$FFFF
	sta	selectStart
	rts
	end

****************************************************************
*
*  SetTabs - set file info from the SYSTABS file
*
*  Inputs:
*	language - language number
*
*  Outputs:
*	insert - insert flag
*	autoReturn - auto return falg
*	ruler - tab line
*	newDebug - use the new debug characters?
*
****************************************************************
*
SetTabs	start
	using BufferCommon
r0	equ	0
r2	equ	2
num	equ	4	work number
hand	equ	6	file handle

	subroutine (2:language,4:insert,4:autoReturn,4:ruler,4:newDebug),10

	lda	#0	initialize tab line
	ldy	#254
gta	sta	[ruler],Y
	dey
	dey
	bpl	gta

	ldy	#7	a tab every 8 spaces
gtb	lda	#1
	sta	[ruler],Y
	tya
	clc
	adc	#8
	tay
	cpy	#254
	blt	gtb
	lda	#1	insert mode is on
	sta	[insert]
	sta	[autoReturn]	auto-return is on
	dec	A	use the old debug character format
	sta	[newDebug]

	lda	#14	load the file
	sta	ffPCount
	stz	ffAction
	lda	#$C000
	sta	ffFlags
	lla	ffPathName,systabs
	FastFileGS ffPCount	FastFileGS ffDCB
	bcc	gtc
	ph2	#11	FlagError(11, 0)
	ph2	#0
	jsl	FlagError
	brl	rts
gtc	move4	ffFileHandle,hand	dereference the handle
	ldy	#2
	lda	[hand]
	sta	r0
	lda	[hand],Y
	sta	r2
	jsr	FINDLN	find the tab line
	bcs	sd1
	brl	rt1
;
;  Set the editor defaults
;
sd1	jsr	GETC	set the return flag
	jcs	rt1
	and	#$F
	cmp	#RETURN
	beq	gt2
	sta	[autoReturn]
	jsr	GETC	set the cut mode flag
	jcs	rt1
	and	#$F
	cmp	#RETURN
	beq	gt2
	jsr	GETC	set the wrap mode flag
	jcs	rt1
	and	#$F
	cmp	#RETURN
	beq	gt2
	jsr	GETC	set insert mode flag
	jcs	rt1
	and	#$F
	cmp	#RETURN
	beq	gt2
	sta	[insert]
	jsr	GETC	set the tab mode flag
	jcs	rt1
	and	#$F
	cmp	#RETURN
	beq	gt2
	jsr	GETC	set the text insert mode flag
	jcs	rt1
	and	#$F
	cmp	#RETURN
	beq	gt2
	jsr	GETC	set the debug kind flag
	jcs	rt1
	and	#$F
	cmp	#RETURN
	beq	gt2
	and	#$1
	sta	[newDebug]
	jsr	SKIP	skip to next line
;
;  Get the tab line
;
gt2	ldy	#0	read in the tab line
gt3	phy
	jsr	GETC
	ply
	bcs	rt1
	and	#$0F
	cmp	#RETURN
	beq	rt1
	short M
	sta	[ruler],Y
	long	M
	iny
	cpy	#256
	blt	gt3
rt1	lda	#7	purge the file
	sta	ffAction
	lla	ffPathName,systabs
	FastFileGS ffPCount	FastFile ffDCB
rts	return
;
;  Locatate the correct tab line
;
FINDLN	stz	num
;
;  Get a decimal number
;
fn1	jsr	GETC
	bcs	no
	jsr	SNMID
	bcc	fn2
	and	#$000F
	pha
	lda	num
	ldx	#10
	jsl	~mul2
	clc
	adc	1,S
	plx
	sta	num
	bra	fn1

fn2	cmp	#RETURN	make sure this is the end of line
	bne	no
fn3	lda	num	see if we found the tab line
	cmp	language
	beq	fn4
	jsr	SKIP	skip past settings
	jsr	SKIP	skip past tab line
	brl	FINDLN	next tab
fn4	sec
	rts
;
;  Skip to next line
;
SKIP	jsr	GETC
	bcs	srts
	cmp	#RETURN
	bne	SKIP
srts	rts
;
;  Numeric identification
;
SNMID	cmp	#'0'
	blt	no
	cmp	#'9'+1
	blt	yes
no	clc
	rts

yes	sec
	rts
;
;  GETC - get a character; return C=1 if at end of file
;
GETC	lda	ffFileLength
	beq	yes
	dec	ffFileLength
	lda	[r0]
	inc4	r0
	and	#$00FF
	clc
	rts
;
;  Local data
;
ffPCount	ds	2	FastFile DCB
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

systabs	dosw	'15/SYSTABS'
	end

****************************************************************
*
*  UpperCase - convert a string to uppercase
*
*  Inputs:
*	str - address of the string to convert
*
****************************************************************
*
UpperCase start

	subroutine (4:str),0

	short I,M
	lda	[str]
	tay
	beq	lb3
lb1	lda	[str],Y
	cmp	#'a'
	blt	lb2
	cmp	#'z'+1
	bge	lb2
	and	#$005F
	sta	[str],Y
lb2	dey
	bne	lb1
lb3	long	I,M
	return
	end

****************************************************************
*
*  Characters - Character font
*
****************************************************************
*
Characters start

	dc	b'00111111 11110000'		  @
	dc	b'11110000 00001100'
	dc	b'11110011 11001100'
	dc	b'11110011 00001100'
	dc	b'11110011 11110000'
	dc	b'11110000 00000000'
	dc	b'00111111 11111100'
	dc	b'00000000 00000000'

	dc	b'00111111 11110000'		  A
	dc	b'11110000 00111100'
	dc	b'11110000 00111100'
	dc	b'11110000 00111100'
	dc	b'11111111 11111100'
	dc	b'11110000 00111100'
	dc	b'11110000 00111100'
	dc	b'00000000 00000000'

	dc	b'11111111 11110000'		  B
	dc	b'11110000 00111100'
	dc	b'11110000 00111100'
	dc	b'11111111 11000000'
	dc	b'11110000 00111100'
	dc	b'11110000 00111100'
	dc	b'11111111 11110000'
	dc	b'00000000 00000000'

	dc	b'00111111 11110000'		  C
	dc	b'11110000 00001100'
	dc	b'11110000 00000000'
	dc	b'11110000 00000000'
	dc	b'11110000 00000000'
	dc	b'11110000 00001100'
	dc	b'00111111 11110000'
	dc	b'00000000 00000000'

	dc	b'11111111 11110000'		  D
	dc	b'11110000 00111100'
	dc	b'11110000 00111100'
	dc	b'11110000 00111100'
	dc	b'11110000 00111100'
	dc	b'11110000 00111100'
	dc	b'11111111 11110000'
	dc	b'00000000 00000000'

	dc	b'11111100 11111111'		  E
	dc	b'11111100 00111111'
	dc	b'11111100 00001111'
	dc	b'00000000 00000011'
	dc	b'11111100 00001111'
	dc	b'11111100 00111111'
	dc	b'11111100 11111111'
	dc	b'11111111 11111111'

	dc	b'11111010 10111111'		  F
	dc	b'11101010 10101111'
	dc	b'10101010 10101011'
	dc	b'10101010 10101011'
	dc	b'10101010 10101011'
	dc	b'11101010 10101111'
	dc	b'11111010 10111111'
	dc	b'11111111 11111111'

	dc	b'01011111 11010111'		  G
	dc	b'01010111 01010111'
	dc	b'11010101 01011111'
	dc	b'11110101 01111111'
	dc	b'11010101 01011111'
	dc	b'01010111 01010111'
	dc	b'01011111 11010111'
	dc	b'11111111 11111111'

	dc	b'11110000 00111100'		  H
	dc	b'11110000 00111100'
	dc	b'11110000 00111100'
	dc	b'11111111 11111100'
	dc	b'11110000 00111100'
	dc	b'11110000 00111100'
	dc	b'11110000 00111100'
	dc	b'00000000 00000000'

	dc	b'00111111 11000000'		  I
	dc	b'00001111 00000000'
	dc	b'00001111 00000000'
	dc	b'00001111 00000000'
	dc	b'00001111 00000000'
	dc	b'00001111 00000000'
	dc	b'00111111 11000000'
	dc	b'00000000 00000000'

	dc	b'00000000 11110000'		  J
	dc	b'00000000 11110000'
	dc	b'00000000 11110000'
	dc	b'00000000 11110000'
	dc	b'00000000 11110000'
	dc	b'11110000 11110000'
	dc	b'00111111 11000000'
	dc	b'00000000 00000000'

	dc	b'11110000 00111100'		  K
	dc	b'11110000 11110000'
	dc	b'11110011 11000000'
	dc	b'11111111 00000000'
	dc	b'11110011 11000000'
	dc	b'11110000 11110000'
	dc	b'11110000 00111100'
	dc	b'00000000 00000000'

	dc	b'11110000 00000000'		  L
	dc	b'11110000 00000000'
	dc	b'11110000 00000000'
	dc	b'11110000 00000000'
	dc	b'11110000 00000000'
	dc	b'11110000 00000000'
	dc	b'11111111 11111100'
	dc	b'00000000 00000000'

	dc	b'11000000 00001100'		  M
	dc	b'11110000 00111100'
	dc	b'11111111 11111100'
	dc	b'11110011 00111100'
	dc	b'11110000 00111100'
	dc	b'11110000 00111100'
	dc	b'11110000 00111100'
	dc	b'00000000 00000000'

	dc	b'11000000 00111100'		  N
	dc	b'11110000 00111100'
	dc	b'11111100 00111100'
	dc	b'11111111 11111100'
	dc	b'11110000 11111100'
	dc	b'11110000 00111100'
	dc	b'11110000 00001100'
	dc	b'00000000 00000000'

	dc	b'00111111 11110000'		  O
	dc	b'11110000 00111100'
	dc	b'11110000 00111100'
	dc	b'11110000 00111100'
	dc	b'11110000 00111100'
	dc	b'11110000 00111100'
	dc	b'00111111 11110000'
	dc	b'00000000 00000000'

	dc	b'11111111 11110000'		  P
	dc	b'11110000 00111100'
	dc	b'11110000 00111100'
	dc	b'11111111 11110000'
	dc	b'11110000 00000000'
	dc	b'11110000 00000000'
	dc	b'11110000 00000000'
	dc	b'00000000 00000000'

	dc	b'11111111 11111111'		  Q
	dc	b'11000011 00001111'
	dc	b'00110011 00110011'
	dc	b'11000000 00001111'
	dc	b'00110011 00110011'
	dc	b'11000011 00001111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  R
	dc	b'11111111 11111111'
	dc	b'11111111 11110011'
	dc	b'11111111 11001111'
	dc	b'00111111 00111111'
	dc	b'11001100 11111111'
	dc	b'11110011 11111111'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  S
	dc	b'11111100 11111111'
	dc	b'11110000 00111111'
	dc	b'11000000 00001111'
	dc	b'11110000 00111111'
	dc	b'11111100 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'

	dc	b'11111111 00111111'		  T
	dc	b'11001100 11001111'
	dc	b'00000000 00000011'
	dc	b'00000000 00001111'
	dc	b'00000000 00001111'
	dc	b'00000000 00000011'
	dc	b'11000011 00001111'
	dc	b'11111111 11111111'

	dc	b'11110000 00111100'		  U
	dc	b'11110000 00111100'
	dc	b'11110000 00111100'
	dc	b'11110000 00111100'
	dc	b'11110000 00111100'
	dc	b'11110000 00111100'
	dc	b'00111111 11110000'
	dc	b'00000000 00000000'

	dc	b'11110000 00111100'		  V
	dc	b'11110000 00111100'
	dc	b'11110000 00111100'
	dc	b'11110000 00111100'
	dc	b'11110000 00111100'
	dc	b'00111100 11110000'
	dc	b'00001111 11000000'
	dc	b'00000000 00000000'

	dc	b'11110000 00111100'		  W
	dc	b'11110000 00111100'
	dc	b'11110000 00111100'
	dc	b'11110011 00111100'
	dc	b'11111111 11111100'
	dc	b'11110000 00111100'
	dc	b'11000000 00001100'
	dc	b'00000000 00000000'

	dc	b'11110000 00111100'		  X
	dc	b'00111100 11110000'
	dc	b'00001111 11000000'
	dc	b'00001111 11000000'
	dc	b'00001111 11000000'
	dc	b'00111100 11110000'
	dc	b'11110000 00111100'
	dc	b'00000000 00000000'

	dc	b'11110000 11110000'		  Y
	dc	b'11110000 11110000'
	dc	b'11110000 11110000'
	dc	b'00111111 11000000'
	dc	b'00001111 00000000'
	dc	b'00001111 00000000'
	dc	b'00001111 00000000'
	dc	b'00000000 00000000'

	dc	b'11111111 11111100'		  Z
	dc	b'00000000 00111100'
	dc	b'00000000 11110000'
	dc	b'00000011 11000000'
	dc	b'00001111 00000000'
	dc	b'00111100 00000000'
	dc	b'11111111 11111100'
	dc	b'00000000 00000000'

	dc	b'00001111 11110000'		  [
	dc	b'00001111 00000000'
	dc	b'00001111 00000000'
	dc	b'00001111 00000000'
	dc	b'00001111 00000000'
	dc	b'00001111 00000000'
	dc	b'00001111 11110000'
	dc	b'00000000 00000000'

	dc	b'00000000 00000000'		  \
	dc	b'11110000 00000000'
	dc	b'00111100 00000000'
	dc	b'00001111 00000000'
	dc	b'00000011 11000000'
	dc	b'00000000 11110000'
	dc	b'00000000 00000000'
	dc	b'00000000 00000000'

	dc	b'00111111 11000000'		  ]
	dc	b'00000011 11000000'
	dc	b'00000011 11000000'
	dc	b'00000011 11000000'
	dc	b'00000011 11000000'
	dc	b'00000011 11000000'
	dc	b'00111111 11000000'
	dc	b'00000000 00000000'

	dc	b'00001111 00000000'		  ^
	dc	b'00111111 11000000'
	dc	b'11110000 11110000'
	dc	b'00000000 00000000'
	dc	b'00000000 00000000'
	dc	b'00000000 00000000'
	dc	b'00000000 00000000'
	dc	b'00000000 00000000'

	dc	b'00000000 00000000'		  _
	dc	b'00000000 00000000'
	dc	b'00000000 00000000'
	dc	b'00000000 00000000'
	dc	b'00000000 00000000'
	dc	b'00000000 00000000'
	dc	b'11111111 11111100'
	dc	b'00000000 00000000'

	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'

	dc	b'11110000 11111111'		  !
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11111111 11111111'
	dc	b'11110000 11111111'
	dc	b'11111111 11111111'

	dc	b'11000011 00001111'		  "
	dc	b'11000011 00001111'
	dc	b'11000011 00001111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'

	dc	b'11000011 00001111'		  #
	dc	b'11000011 00001111'
	dc	b'00000000 00000011'
	dc	b'11000011 00001111'
	dc	b'00000000 00000011'
	dc	b'11000011 00001111'
	dc	b'11000011 00001111'
	dc	b'11111111 11111111'

	dc	b'11111100 11111111'		  $
	dc	b'11000000 00000011'
	dc	b'00001100 11111111'
	dc	b'11000000 00001111'
	dc	b'11111100 11000011'
	dc	b'00000000 00001111'
	dc	b'11111100 11111111'
	dc	b'11111111 11111111'

	dc	b'11000011 11111111'		  %
	dc	b'11000011 00001111'
	dc	b'11111100 00111111'
	dc	b'11110000 11111111'
	dc	b'11000011 11111111'
	dc	b'00001100 00111111'
	dc	b'11111100 00111111'
	dc	b'11111111 11111111'

	dc	b'11110000 00111111'		  &
	dc	b'11000011 00001111'
	dc	b'11000011 00001111'
	dc	b'11110000 00111111'
	dc	b'11000011 00110011'
	dc	b'00001111 00001111'
	dc	b'11000000 00110011'
	dc	b'11111111 11111111'

	dc	b'11111100 00111111'		  '
	dc	b'11111100 00111111'
	dc	b'11111100 00111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'

	dc	b'11111100 00111111'		  (
	dc	b'11110000 11111111'
	dc	b'11000011 11111111'
	dc	b'11000011 11111111'
	dc	b'11000011 11111111'
	dc	b'11110000 11111111'
	dc	b'11111100 00111111'
	dc	b'11111111 11111111'

	dc	b'11110000 11111111'		  )
	dc	b'11111100 00111111'
	dc	b'11111111 00001111'
	dc	b'11111111 00001111'
	dc	b'11111111 00001111'
	dc	b'11111100 00111111'
	dc	b'11110000 11111111'
	dc	b'11111111 11111111'

	dc	b'11111100 11111111'		  *
	dc	b'00001100 11000011'
	dc	b'11000000 00001111'
	dc	b'11110000 00111111'
	dc	b'11000000 00001111'
	dc	b'00001100 11000011'
	dc	b'11111100 11111111'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  +
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'00000000 00001111'
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  ,
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11000011 11111111'

	dc	b'11111111 11111111'		  -
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'00000000 00000011'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  .
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111100 00111111'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  /
	dc	b'11111111 11000011'
	dc	b'11111111 00001111'
	dc	b'11111100 00111111'
	dc	b'11110000 11111111'
	dc	b'11000011 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'

	dc	b'11000000 00000011'		  0
	dc	b'00001111 11000011'
	dc	b'00001111 00000011'
	dc	b'00001100 11000011'
	dc	b'00000011 11000011'
	dc	b'00001111 11000011'
	dc	b'00000000 00001111'
	dc	b'11111111 11111111'

	dc	b'11110000 11111111'		  1
	dc	b'11000000 11111111'
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11000000 00111111'
	dc	b'11111111 11111111'

	dc	b'11000000 00001111'		  2
	dc	b'00001111 11000011'
	dc	b'11111111 11000011'
	dc	b'11111111 00001111'
	dc	b'11110000 11111111'
	dc	b'00001111 11111111'
	dc	b'00000000 00000011'
	dc	b'11111111 11111111'

	dc	b'00000000 00000011'		  3
	dc	b'11111111 11000011'
	dc	b'11111111 00001111'
	dc	b'11111100 00111111'
	dc	b'11111111 00001111'
	dc	b'00001111 11000011'
	dc	b'11000000 00001111'
	dc	b'11111111 11111111'

	dc	b'11111100 00001111'		  4
	dc	b'11110000 00001111'
	dc	b'11000011 00001111'
	dc	b'00001111 00001111'
	dc	b'00000000 00000011'
	dc	b'11111111 00001111'
	dc	b'11111111 00001111'
	dc	b'11111111 11111111'

	dc	b'00000000 00000011'		  5
	dc	b'00001111 11111111'
	dc	b'00000000 11111111'
	dc	b'11111111 00001111'
	dc	b'11111111 11000011'
	dc	b'00001111 11000011'
	dc	b'11000000 00001111'
	dc	b'11111111 11111111'

	dc	b'11110000 00001111'		  6
	dc	b'11000011 11111111'
	dc	b'00001111 11111111'
	dc	b'00000000 00001111'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'11000000 00001111'
	dc	b'11111111 11111111'

	dc	b'00000000 00000011'		  7
	dc	b'11111111 11000011'
	dc	b'11111111 00001111'
	dc	b'11111100 00111111'
	dc	b'11110000 11111111'
	dc	b'11000011 11111111'
	dc	b'11000011 11111111'
	dc	b'11111111 11111111'

	dc	b'11000000 00001111'		  8
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'11110000 00111111'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'11000000 00001111'
	dc	b'11111111 11111111'

	dc	b'11000000 00001111'		  9
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'11000000 00000011'
	dc	b'11111111 11000011'
	dc	b'11111111 00001111'
	dc	b'11000000 00111111'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  :
	dc	b'11111111 11111111'
	dc	b'11110000 11111111'
	dc	b'11111111 11111111'
	dc	b'11110000 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  ;
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11110000 11111111'
	dc	b'11111111 11111111'
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11000011 11111111'

	dc	b'11111111 00001111'		  <
	dc	b'11111100 00111111'
	dc	b'11110000 11111111'
	dc	b'11000011 11111111'
	dc	b'11110000 11111111'
	dc	b'11111100 00111111'
	dc	b'11111111 00001111'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  =
	dc	b'11111111 11111111'
	dc	b'11000000 00001111'
	dc	b'11111111 11111111'
	dc	b'11000000 00001111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'

	dc	b'11000011 11111111'		  >
	dc	b'11110000 11111111'
	dc	b'11111100 00111111'
	dc	b'11111111 00001111'
	dc	b'11111100 00111111'
	dc	b'11110000 11111111'
	dc	b'11000011 11111111'
	dc	b'11111111 11111111'

	dc	b'11000000 00001111'		  ?
	dc	b'00001111 11000011'
	dc	b'11111111 00001111'
	dc	b'11111100 00111111'
	dc	b'11111100 00111111'
	dc	b'11111111 11111111'
	dc	b'11111100 00111111'
	dc	b'11111111 11111111'

	dc	b'11000000 00001111'		  @
	dc	b'00001111 11110011'
	dc	b'00001100 00110011'
	dc	b'00001100 11110011'
	dc	b'00001100 00001111'
	dc	b'00001111 11111111'
	dc	b'11000000 00000011'
	dc	b'11111111 11111111'

	dc	b'11000000 00001111'		  A
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00000000 00000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'11111111 11111111'

	dc	b'00000000 00001111'		  B
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00000000 00111111'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00000000 00001111'
	dc	b'11111111 11111111'

	dc	b'11000000 00001111'		  C
	dc	b'00001111 11110011'
	dc	b'00001111 11111111'
	dc	b'00001111 11111111'
	dc	b'00001111 11111111'
	dc	b'00001111 11110011'
	dc	b'11000000 00001111'
	dc	b'11111111 11111111'

	dc	b'00000000 00001111'		  D
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00000000 00001111'
	dc	b'11111111 11111111'

	dc	b'00000000 00000011'		  E
	dc	b'00001111 11111111'
	dc	b'00001111 11111111'
	dc	b'00000000 00001111'
	dc	b'00001111 11111111'
	dc	b'00001111 11111111'
	dc	b'00000000 00000011'
	dc	b'11111111 11111111'

	dc	b'00000000 00000011'		  F
	dc	b'00001111 11111111'
	dc	b'00001111 11111111'
	dc	b'00000000 00001111'
	dc	b'00001111 11111111'
	dc	b'00001111 11111111'
	dc	b'00001111 11111111'
	dc	b'11111111 11111111'

	dc	b'11000000 00001111'		  G
	dc	b'00001111 11110011'
	dc	b'00001111 11111111'
	dc	b'00001111 11111111'
	dc	b'00001111 00000011'
	dc	b'00001111 11000011'
	dc	b'11000000 00000011'
	dc	b'11111111 11111111'

	dc	b'00001111 11000011'		  H
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00000000 00000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'11111111 11111111'

	dc	b'11000000 00111111'		  I
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11000000 00111111'
	dc	b'11111111 11111111'

	dc	b'11111111 00001111'		  J
	dc	b'11111111 00001111'
	dc	b'11111111 00001111'
	dc	b'11111111 00001111'
	dc	b'11111111 00001111'
	dc	b'00001111 00001111'
	dc	b'11000000 00111111'
	dc	b'11111111 11111111'

	dc	b'00001111 11000011'		  K
	dc	b'00001111 00001111'
	dc	b'00001100 00111111'
	dc	b'00000000 11111111'
	dc	b'00001100 00111111'
	dc	b'00001111 00001111'
	dc	b'00001111 11000011'
	dc	b'11111111 11111111'

	dc	b'00001111 11111111'		  L
	dc	b'00001111 11111111'
	dc	b'00001111 11111111'
	dc	b'00001111 11111111'
	dc	b'00001111 11111111'
	dc	b'00001111 11111111'
	dc	b'00000000 00000011'
	dc	b'11111111 11111111'

	dc	b'00111111 11110011'		  M
	dc	b'00001111 11000011'
	dc	b'00000000 00000011'
	dc	b'00001100 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'11111111 11111111'

	dc	b'00111111 11000011'		  N
	dc	b'00001111 11000011'
	dc	b'00000011 11000011'
	dc	b'00000000 00000011'
	dc	b'00001111 00000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11110011'
	dc	b'11111111 11111111'

	dc	b'11000000 00001111'		  O
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'11000000 00001111'
	dc	b'11111111 11111111'

	dc	b'00000000 00001111'		  P
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00000000 00001111'
	dc	b'00001111 11111111'
	dc	b'00001111 11111111'
	dc	b'00001111 11111111'
	dc	b'11111111 11111111'

	dc	b'11000000 00001111'		  Q
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001100 00000011'
	dc	b'00001111 00001111'
	dc	b'11000000 11000011'
	dc	b'11111111 11111111'

	dc	b'00000000 00001111'		  R
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00000000 00001111'
	dc	b'00001100 00111111'
	dc	b'00001111 00001111'
	dc	b'00001111 11000011'
	dc	b'11111111 11111111'

	dc	b'11000000 00001111'		  S
	dc	b'00001111 11110011'
	dc	b'00001111 11111111'
	dc	b'11000000 00001111'
	dc	b'11111111 11000011'
	dc	b'00111111 11000011'
	dc	b'11000000 00001111'
	dc	b'11111111 11111111'

	dc	b'00000000 00000011'		  T
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11111111 11111111'

	dc	b'00001111 11000011'		  U
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'11000000 00001111'
	dc	b'11111111 11111111'

	dc	b'00001111 11000011'		  V
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'11000011 00001111'
	dc	b'11110000 00111111'
	dc	b'11111111 11111111'

	dc	b'00001111 11000011'		  W
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001100 11000011'
	dc	b'00000000 00000011'
	dc	b'00001111 11000011'
	dc	b'00111111 11110011'
	dc	b'11111111 11111111'

	dc	b'00001111 11000011'		  X
	dc	b'11000011 00001111'
	dc	b'11110000 00111111'
	dc	b'11110000 00111111'
	dc	b'11110000 00111111'
	dc	b'11000011 00001111'
	dc	b'00001111 11000011'
	dc	b'11111111 11111111'

	dc	b'00001111 00001111'		  Y
	dc	b'00001111 00001111'
	dc	b'00001111 00001111'
	dc	b'11000000 00111111'
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11111111 11111111'

	dc	b'00000000 00000011'		  Z
	dc	b'11111111 11000011'
	dc	b'11111111 00001111'
	dc	b'11111100 00111111'
	dc	b'11110000 11111111'
	dc	b'11000011 11111111'
	dc	b'00000000 00000011'
	dc	b'11111111 11111111'

	dc	b'11110000 00001111'		  [
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11110000 00001111'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  \
	dc	b'00001111 11111111'
	dc	b'11000011 11111111'
	dc	b'11110000 11111111'
	dc	b'11111100 00111111'
	dc	b'11111111 00001111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'

	dc	b'11000000 00111111'		  ]
	dc	b'11111100 00111111'
	dc	b'11111100 00111111'
	dc	b'11111100 00111111'
	dc	b'11111100 00111111'
	dc	b'11111100 00111111'
	dc	b'11000000 00111111'
	dc	b'11111111 11111111'

	dc	b'11110000 11111111'		  ^
	dc	b'11000000 00111111'
	dc	b'00001111 00001111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  _
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'00000000 00000011'
	dc	b'11111111 11111111'

	dc	b'11110000 11111111'		  `
	dc	b'11110000 11111111'
	dc	b'11111100 00111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  a
	dc	b'11111111 11111111'
	dc	b'11000000 00001111'
	dc	b'11111111 11000011'
	dc	b'11000000 00000011'
	dc	b'00001111 11000011'
	dc	b'11000000 00000011'
	dc	b'11111111 11111111'

	dc	b'00001111 11111111'		  b
	dc	b'00001111 11111111'
	dc	b'00000000 00001111'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00000000 00001111'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  c
	dc	b'11111111 11111111'
	dc	b'11000000 00000011'
	dc	b'00001111 11111111'
	dc	b'00001111 11111111'
	dc	b'00001111 11111111'
	dc	b'11000000 00000011'
	dc	b'11111111 11111111'

	dc	b'11111111 11000011'		  d
	dc	b'11111111 11000011'
	dc	b'11000000 00000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'11000000 00000011'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  e
	dc	b'11111111 11111111'
	dc	b'11000000 00001111'
	dc	b'00001111 11000011'
	dc	b'00000000 00000011'
	dc	b'00001111 11111111'
	dc	b'11000000 00000011'
	dc	b'11111111 11111111'

	dc	b'11110000 00001111'		  f
	dc	b'11000011 11000011'
	dc	b'11000011 11111111'
	dc	b'00000000 00111111'
	dc	b'11000011 11111111'
	dc	b'11000011 11111111'
	dc	b'11000011 11111111'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  g
	dc	b'11111111 11111111'
	dc	b'11000000 00001111'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'11000000 00000011'
	dc	b'11111111 11000011'
	dc	b'11000000 00001111'

	dc	b'00001111 11111111'		  h
	dc	b'00001111 11111111'
	dc	b'00000000 00001111'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'11111111 11111111'

	dc	b'11110000 11111111'		  i
	dc	b'11111111 11111111'
	dc	b'11000000 11111111'
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11000000 00111111'
	dc	b'11111111 11111111'

	dc	b'11111111 00001111'		  j
	dc	b'11111111 11111111'
	dc	b'11111100 00001111'
	dc	b'11111111 00001111'
	dc	b'11111111 00001111'
	dc	b'11111111 00001111'
	dc	b'11000011 00001111'
	dc	b'11110000 00111111'

	dc	b'00001111 11111111'		  k
	dc	b'00001111 11111111'
	dc	b'00001111 00001111'
	dc	b'00001100 00111111'
	dc	b'00000000 11111111'
	dc	b'00001100 00111111'
	dc	b'00001111 00001111'
	dc	b'11111111 11111111'

	dc	b'11000000 11111111'		  l
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11000000 00111111'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  m
	dc	b'11111111 11111111'
	dc	b'00001111 11000011'
	dc	b'00000011 00000011'
	dc	b'00001100 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  n
	dc	b'11111111 11111111'
	dc	b'00000000 00001111'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  o
	dc	b'11111111 11111111'
	dc	b'11000000 00001111'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'11000000 00001111'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  p
	dc	b'11111111 11111111'
	dc	b'00000000 00001111'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00000000 00001111'
	dc	b'00001111 11111111'
	dc	b'00001111 11111111'

	dc	b'11111111 11111111'		  q
	dc	b'11111111 11111111'
	dc	b'11000000 00000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'11000000 00000011'
	dc	b'11111111 11000011'
	dc	b'11111111 11000011'

	dc	b'11111111 11111111'		  r
	dc	b'11111111 11111111'
	dc	b'00110000 00001111'
	dc	b'00001111 11000011'
	dc	b'00001111 11111111'
	dc	b'00001111 11111111'
	dc	b'00001111 11111111'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  s
	dc	b'11111111 11111111'
	dc	b'11000000 00000011'
	dc	b'00001111 11111111'
	dc	b'11000000 00001111'
	dc	b'11111111 11000011'
	dc	b'00000000 00001111'
	dc	b'11111111 11111111'

	dc	b'11110000 11111111'		  t
	dc	b'11110000 11111111'
	dc	b'00000000 00001111'
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11110000 11000011'
	dc	b'11111100 00001111'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  u
	dc	b'11111111 11111111'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'11000000 00001111'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  v
	dc	b'11111111 11111111'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'11000011 00001111'
	dc	b'11110000 00111111'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  w
	dc	b'11111111 11111111'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001100 11000011'
	dc	b'00000011 00000011'
	dc	b'00001111 11000011'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  x
	dc	b'11111111 11111111'
	dc	b'00001111 11000011'
	dc	b'11000011 00001111'
	dc	b'11110000 00111111'
	dc	b'11000011 00001111'
	dc	b'00001111 11000011'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  y
	dc	b'11111111 11111111'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'11000000 00000011'
	dc	b'11111111 11000011'
	dc	b'11000000 00001111'

	dc	b'11111111 11111111'		  z
	dc	b'11111111 11111111'
	dc	b'00000000 00000011'
	dc	b'11111111 00001111'
	dc	b'11110000 00111111'
	dc	b'11000011 11111111'
	dc	b'00000000 00000011'
	dc	b'11111111 11111111'

	dc	b'11111100 00001111'		  {
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11000011 11111111'
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11111100 00001111'
	dc	b'11111111 11111111'

	dc	b'11111100 00111111'		  |
	dc	b'11111100 00111111'
	dc	b'11111100 00111111'
	dc	b'11111100 00111111'
	dc	b'11111100 00111111'
	dc	b'11111100 00111111'
	dc	b'11111100 00111111'
	dc	b'11111100 00111111'

	dc	b'11000000 11111111'		  }
	dc	b'11111100 00111111'
	dc	b'11111100 00111111'
	dc	b'11111111 00001111'
	dc	b'11111100 00111111'
	dc	b'11111100 00111111'
	dc	b'11000000 11111111'
	dc	b'11111111 11111111'

	dc	b'11110000 11110011'		  ~
	dc	b'00001100 11000011'
	dc	b'00111100 00111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'

	dc	b'00110011 00110011'		  rub
	dc	b'11001100 11001100'
	dc	b'00110011 00110011'
	dc	b'11001100 11001100'
	dc	b'00110011 00110011'
	dc	b'11001100 11001100'
	dc	b'00110011 00110011'
	dc	b'11001100 11001100'

	dc	b'11110011 00111111'		  @
	dc	b'11111111 11111111'
	dc	b'11000000 00001111'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00000000 00000011'
	dc	b'00001111 11000011'
	dc	b'11111111 11111111'

	dc	b'11110000 00111111'		  A
	dc	b'11110011 00111111'
	dc	b'11000000 00001111'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00000000 00000011'
	dc	b'00001111 11000011'
	dc	b'11111111 11111111'

	dc	b'11000000 00001111'		  B
	dc	b'00001111 11110011'
	dc	b'00001111 11111111'
	dc	b'00001111 11111111'
	dc	b'00001111 11110011'
	dc	b'11000000 00001111'
	dc	b'11111111 00111111'
	dc	b'11111100 11111111'

	dc	b'11111111 00111111'		  C
	dc	b'11111100 11111111'
	dc	b'00000000 00000011'
	dc	b'00001111 11111111'
	dc	b'00000000 00001111'
	dc	b'00001111 11111111'
	dc	b'00000000 00000011'
	dc	b'11111111 11111111'

	dc	b'11110011 00111111'		  D
	dc	b'11001100 11111111'
	dc	b'00001111 11000011'
	dc	b'00000011 11000011'
	dc	b'00000000 00000011'
	dc	b'00001111 00000011'
	dc	b'00001111 11000011'
	dc	b'11111111 11111111'

	dc	b'11110011 00111111'		  E
	dc	b'11000000 00001111'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'11000000 00001111'
	dc	b'11111111 11111111'

	dc	b'11110011 00111111'		  F
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'11000000 00001111'
	dc	b'11111111 11111111'

	dc	b'11111111 00111111'		  G
	dc	b'11111100 11111111'
	dc	b'11000000 00001111'
	dc	b'11111111 11000011'
	dc	b'11000000 00000011'
	dc	b'00001111 11000011'
	dc	b'11000000 00000011'
	dc	b'11111111 11111111'

	dc	b'11111100 11111111'		  H
	dc	b'11111111 00111111'
	dc	b'11000000 00001111'
	dc	b'11111111 11000011'
	dc	b'11000000 00000011'
	dc	b'00001111 11000011'
	dc	b'11000000 00000011'
	dc	b'11111111 11111111'

	dc	b'11111100 11111111'		  I
	dc	b'11110011 00111111'
	dc	b'11000000 00001111'
	dc	b'11111111 11000011'
	dc	b'11000000 00000011'
	dc	b'00001111 11000011'
	dc	b'11000000 00000011'
	dc	b'11111111 11111111'

	dc	b'11110011 00111111'		  J
	dc	b'11111111 11111111'
	dc	b'11000000 00001111'
	dc	b'11111111 11000011'
	dc	b'11000000 00000011'
	dc	b'00001111 11000011'
	dc	b'11000000 00000011'
	dc	b'11111111 11111111'

	dc	b'11111100 11001111'		  K
	dc	b'11110011 00111111'
	dc	b'11000000 00001111'
	dc	b'11111111 11000011'
	dc	b'11000000 00000011'
	dc	b'00001111 11000011'
	dc	b'11000000 00000011'
	dc	b'11111111 11111111'

	dc	b'11110000 00111111'		  L
	dc	b'11110011 00111111'
	dc	b'11000000 00001111'
	dc	b'11111111 11000011'
	dc	b'11000000 00000011'
	dc	b'00001111 11000011'
	dc	b'11000000 00000011'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  M
	dc	b'11111111 11111111'
	dc	b'11000000 00000011'
	dc	b'00001111 11111111'
	dc	b'00001111 11111111'
	dc	b'00001111 11111111'
	dc	b'11000000 00000011'
	dc	b'11111111 00111111'

	dc	b'11111111 00111111'		  N
	dc	b'11111100 11111111'
	dc	b'11000000 00001111'
	dc	b'00001111 11000011'
	dc	b'00000000 00000011'
	dc	b'00001111 11111111'
	dc	b'11000000 00000011'
	dc	b'11111111 11111111'

	dc	b'11111100 11111111'		  O
	dc	b'11111111 00111111'
	dc	b'11000000 00001111'
	dc	b'00001111 11000011'
	dc	b'00000000 00000011'
	dc	b'00001111 11111111'
	dc	b'11000000 00000011'
	dc	b'11111111 11111111'

	dc	b'11111100 11111111'		  P
	dc	b'11110011 00111111'
	dc	b'11000000 00001111'
	dc	b'00001111 11000011'
	dc	b'00000000 00000011'
	dc	b'00001111 11111111'
	dc	b'11000000 00000011'
	dc	b'11111111 11111111'

	dc	b'11110011 00111111'		  Q
	dc	b'11111111 11111111'
	dc	b'11000000 00001111'
	dc	b'00001111 11000011'
	dc	b'00000000 00000011'
	dc	b'00001111 11111111'
	dc	b'11000000 00000011'
	dc	b'11111111 11111111'

	dc	b'11111100 11111111'		  R
	dc	b'11110011 11111111'
	dc	b'11000000 11111111'
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11000000 00111111'
	dc	b'11111111 11111111'

	dc	b'11110011 11111111'		  S
	dc	b'11111100 11111111'
	dc	b'11000000 11111111'
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11000000 00111111'
	dc	b'11111111 11111111'

	dc	b'11111100 11111111'		  T
	dc	b'11110011 00111111'
	dc	b'11000000 11111111'
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11000000 00111111'
	dc	b'11111111 11111111'

	dc	b'11110011 00111111'		  U
	dc	b'11111111 11111111'
	dc	b'11000000 11111111'
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11000000 00111111'
	dc	b'11111111 11111111'

	dc	b'11110011 00111111'		  V
	dc	b'11001100 11111111'
	dc	b'00000000 00001111'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'11111111 11111111'

	dc	b'11111111 00111111'		  W
	dc	b'11111100 11111111'
	dc	b'11000000 00001111'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'11000000 00001111'
	dc	b'11111111 11111111'

	dc	b'11111100 11111111'		  X
	dc	b'11111111 00111111'
	dc	b'11000000 00001111'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'11000000 00001111'
	dc	b'11111111 11111111'

	dc	b'11111100 11111111'		  Y
	dc	b'11110011 00111111'
	dc	b'11000000 00001111'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'11000000 00001111'
	dc	b'11111111 11111111'

	dc	b'11110011 00111111'		  Z
	dc	b'11111111 11111111'
	dc	b'11000000 00001111'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'11000000 00001111'
	dc	b'11111111 11111111'

	dc	b'11111100 11001111'		  [
	dc	b'11110011 00111111'
	dc	b'11000000 00001111'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'11000000 00001111'
	dc	b'11111111 11111111'

	dc	b'11111111 00111111'		  \
	dc	b'11111100 11111111'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'11000000 00001111'
	dc	b'11111111 11111111'

	dc	b'11111100 11111111'		  ]
	dc	b'11111111 00111111'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'11000000 00001111'
	dc	b'11111111 11111111'

	dc	b'11111100 11111111'		  ^
	dc	b'11110011 00111111'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'11000000 00001111'
	dc	b'11111111 11111111'

	dc	b'11110011 00111111'		  _
	dc	b'11111111 11111111'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'11000000 00001111'
	dc	b'11111111 11111111'

	dc	b'11111100 11111111'
	dc	b'11000000 00001111'
	dc	b'11111100 11111111'
	dc	b'11111100 11111111'
	dc	b'11111100 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'

	dc	b'11110000 11111111'		  !
	dc	b'11001111 00111111'
	dc	b'11110000 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'

	dc	b'11111100 11111111'		  "
	dc	b'11000000 00001111'
	dc	b'00001100 11111111'
	dc	b'00001100 11111111'
	dc	b'11000000 00001111'
	dc	b'11111100 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'

	dc	b'11110000 00111111'		  #
	dc	b'11000011 11001111'
	dc	b'11000011 11111111'
	dc	b'00000000 11111111'
	dc	b'11000011 11111111'
	dc	b'11000011 11110011'
	dc	b'00000000 00001111'
	dc	b'11111111 11111111'

	dc	b'11111100 11111111'		  $
	dc	b'11110011 00111111'
	dc	b'11110000 11111111'
	dc	b'11110011 00111111'
	dc	b'11111100 00111111'
	dc	b'11110011 00111111'
	dc	b'11111100 11111111'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  %
	dc	b'11110000 00111111'
	dc	b'11000000 00001111'
	dc	b'11000000 00001111'
	dc	b'11000000 00001111'
	dc	b'11110000 00111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'

	dc	b'11000000 00000011'		  &
	dc	b'00001111 00110011'
	dc	b'00001111 00110011'
	dc	b'00001111 00110011'
	dc	b'11000000 00110011'
	dc	b'11111111 00110011'
	dc	b'11111111 00110011'
	dc	b'11111111 11111111'

	dc	b'11000000 00001111'		  '
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001100 00001111'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001100 00001111'
	dc	b'11111111 11111111'

	dc	b'11000000 00001111'		  (
	dc	b'00110000 00110011'
	dc	b'00110011 00110011'
	dc	b'00110000 11110011'
	dc	b'00110011 00110011'
	dc	b'00110011 00110011'
	dc	b'11000000 00001111'
	dc	b'11111111 11111111'

	dc	b'11000000 00001111'		  )
	dc	b'00111111 11110011'
	dc	b'00110000 00110011'
	dc	b'00110011 11110011'
	dc	b'00110000 00110011'
	dc	b'00111111 11110011'
	dc	b'11000000 00001111'
	dc	b'11111111 11111111'

	dc	b'00000000 11110011'		  *
	dc	b'11001100 00000011'
	dc	b'11001100 00000011'
	dc	b'11001100 11110011'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'

	dc	b'11111100 00111111'		  +
	dc	b'11111100 00111111'
	dc	b'11110000 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'

	dc	b'11110011 00111111'		  ,
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  -
	dc	b'11111111 00111111'
	dc	b'11000000 00001111'
	dc	b'11111100 11111111'
	dc	b'11000000 00001111'
	dc	b'11110011 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'

	dc	b'11000000 00000011'		  .
	dc	b'00001100 00111111'
	dc	b'00001100 00111111'
	dc	b'00000000 00001111'
	dc	b'00001100 00111111'
	dc	b'00001100 00111111'
	dc	b'00001100 00000011'
	dc	b'11111111 11111111'

	dc	b'11000000 00000011'		  /
	dc	b'00001111 11000011'
	dc	b'00001111 00000011'
	dc	b'00001100 11000011'
	dc	b'00000011 11000011'
	dc	b'00001111 11000011'
	dc	b'00000000 00001111'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  0
	dc	b'11111111 11111111'
	dc	b'11000011 00001111'
	dc	b'00111100 11110011'
	dc	b'11000011 00001111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'

	dc	b'11110000 11111111'		  1
	dc	b'11110000 11111111'
	dc	b'00000000 00001111'
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11111111 11111111'
	dc	b'00000000 00001111'
	dc	b'11111111 11111111'

	dc	b'11111100 00111111'		  2
	dc	b'11110000 11111111'
	dc	b'11000011 11111111'
	dc	b'11110000 11111111'
	dc	b'11111100 00111111'
	dc	b'11111111 11111111'
	dc	b'11000000 00111111'
	dc	b'11111111 11111111'

	dc	b'11000011 11111111'		  3
	dc	b'11110000 11111111'
	dc	b'11111100 00111111'
	dc	b'11110000 11111111'
	dc	b'11000011 11111111'
	dc	b'11111111 11111111'
	dc	b'11000000 00111111'
	dc	b'11111111 11111111'

	dc	b'00001111 00001111'		  4
	dc	b'00001111 00001111'
	dc	b'11000000 00111111'
	dc	b'00000000 00001111'
	dc	b'11110000 11111111'
	dc	b'00000000 00001111'
	dc	b'11110000 11111111'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  5
	dc	b'11111111 11111111'
	dc	b'11000011 11000011'
	dc	b'11000011 11000011'
	dc	b'11000011 11000011'
	dc	b'11000011 11000011'
	dc	b'11000000 00001111'
	dc	b'00001111 11111111'

	dc	b'11000000 00111111'		  6
	dc	b'11111111 00001111'
	dc	b'11111111 11000011'
	dc	b'11000000 00000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'11000000 00001111'
	dc	b'11111111 11111111'

	dc	b'00000000 00000011'		  7
	dc	b'11000011 11111111'
	dc	b'11110000 11111111'
	dc	b'11111100 00111111'
	dc	b'11110000 11111111'
	dc	b'11000011 11111111'
	dc	b'00000000 00000011'
	dc	b'11111111 11111111'

	dc	b'00000000 00000011'		  8
	dc	b'11000011 00001111'
	dc	b'11000011 00001111'
	dc	b'11000011 00001111'
	dc	b'11000011 00001111'
	dc	b'11000011 00001111'
	dc	b'11000011 00001111'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  9
	dc	b'11111111 11000011'
	dc	b'00000000 00001111'
	dc	b'11000011 00001111'
	dc	b'11000011 00001111'
	dc	b'11000011 00001111'
	dc	b'11000011 00001111'
	dc	b'11111111 11111111'

	dc	b'11111100 00111111'		  :
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11000011 11111111'
	dc	b'11111111 11111111'

	dc	b'11000000 00001111'		  a
	dc	b'11111111 11000011'
	dc	b'11000000 00000011'
	dc	b'00001111 11000011'
	dc	b'11000000 00000011'
	dc	b'11111111 11111111'
	dc	b'00000000 00000011'
	dc	b'11111111 11111111'

	dc	b'11000000 00001111'		  <
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'11000000 00001111'
	dc	b'11111111 11111111'
	dc	b'00000000 00000011'
	dc	b'11111111 11111111'

	dc	b'11000000 00001111'		  U
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'11000011 00001111'
	dc	b'00000011 00000011'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  >
	dc	b'11111111 11111111'
	dc	b'00000000 00001111'
	dc	b'11110000 11000011'
	dc	b'11001100 00000011'
	dc	b'00001100 11111111'
	dc	b'11000000 00000011'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  ?
	dc	b'11111111 11111111'
	dc	b'11000000 00001111'
	dc	b'00001111 00000011'
	dc	b'00001100 11000011'
	dc	b'00000011 11000011'
	dc	b'11000000 00001111'
	dc	b'11111111 11111111'

	dc	b'11111100 00111111'		  @
	dc	b'11111111 11111111'
	dc	b'11111100 00111111'
	dc	b'11111100 00111111'
	dc	b'11111111 00001111'
	dc	b'00001111 11000011'
	dc	b'11000000 00001111'
	dc	b'11111111 11111111'

	dc	b'11110000 11111111'		  A
	dc	b'11111111 11111111'
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  B
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'00000000 00001111'
	dc	b'11111111 00001111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  C
	dc	b'11111111 11000011'
	dc	b'11111111 00111111'
	dc	b'11111111 00111111'
	dc	b'00111100 11111111'
	dc	b'11001100 11111111'
	dc	b'11110011 11111111'
	dc	b'11111111 11111111'

	dc	b'11111100 00001111'		  D
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11000000 00111111'
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11000011 11111111'

	dc	b'11111111 11111111'		  E
	dc	b'11111111 11001111'
	dc	b'11110000 00111111'
	dc	b'11001111 11001111'
	dc	b'11110000 00111111'
	dc	b'11001111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'

	dc	b'11111100 11111111'		  F
	dc	b'11110000 00111111'
	dc	b'11001111 00001111'
	dc	b'11001111 00001111'
	dc	b'00111111 11000011'
	dc	b'00111111 11000011'
	dc	b'00000000 00000011'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  G
	dc	b'11110000 11000011'
	dc	b'11000011 00001111'
	dc	b'00001100 00111111'
	dc	b'11000011 00001111'
	dc	b'11110000 11000011'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  H
	dc	b'00001100 00111111'
	dc	b'11000011 00001111'
	dc	b'11110000 11000011'
	dc	b'11000011 00001111'
	dc	b'00001100 00111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  I
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11001100 11001111'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  J
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'

	dc	b'11111100 11111111'		  K
	dc	b'11111111 00111111'
	dc	b'11000000 00001111'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00000000 00000011'
	dc	b'00001111 11000011'
	dc	b'11111111 11111111'

	dc	b'11110011 00111111'		  L
	dc	b'11001100 11111111'
	dc	b'11000000 00001111'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00000000 00000011'
	dc	b'00001111 11000011'
	dc	b'11111111 11111111'

	dc	b'11111100 11000011'		  M
	dc	b'11000000 00001111'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'11000000 00001111'
	dc	b'11111111 11111111'

	dc	b'11000000 00000011'		  N
	dc	b'00001100 00111111'
	dc	b'00001100 00111111'
	dc	b'00001100 00001111'
	dc	b'00001100 00111111'
	dc	b'00001100 00111111'
	dc	b'11000000 00000011'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  O
	dc	b'11111111 11111111'
	dc	b'11000000 00001111'
	dc	b'00001100 00110011'
	dc	b'00001100 00000011'
	dc	b'00001100 00111111'
	dc	b'11000000 00000011'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  P
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11000000 00001111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  Q
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'00000000 00000000'
	dc	b'11111111 11111111'

	dc	b'11110011 11001111'		  R
	dc	b'11001111 00111111'
	dc	b'11000011 00001111'
	dc	b'11000011 00001111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'

	dc	b'11000011 00001111'		  S
	dc	b'11000011 00001111'
	dc	b'11110011 11001111'
	dc	b'11001111 00111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'

	dc	b'11111100 11111111'		  T
	dc	b'11110011 11111111'
	dc	b'11110000 11111111'
	dc	b'11110000 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'

	dc	b'11110000 11111111'		  U
	dc	b'11110000 11111111'
	dc	b'11111100 11111111'
	dc	b'11110011 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  V
	dc	b'11110000 11111111'
	dc	b'11111111 11111111'
	dc	b'00000000 00001111'
	dc	b'11111111 11111111'
	dc	b'11110000 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  W
	dc	b'11111100 11111111'
	dc	b'11110011 00111111'
	dc	b'11001111 11001111'
	dc	b'11110011 00111111'
	dc	b'11111100 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'

	dc	b'11110011 00111111'		  X
	dc	b'11111111 11111111'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'00001111 11000011'
	dc	b'11000000 00000011'
	dc	b'11111111 11000011'
	dc	b'11000000 00001111'

	dc	b'01011111 01011111'		  Y
	dc	b'01011111 01011111'
	dc	b'01011111 01011111'
	dc	b'11010101 01111111'
	dc	b'11110101 11111111'
	dc	b'11110101 11111111'
	dc	b'11110101 11111111'
	dc	b'11111111 11111111'

	dc	b'01010101 01010111'		  Z
	dc	b'11111111 11010111'
	dc	b'11111111 01011111'
	dc	b'11111101 01111111'
	dc	b'11110101 11111111'
	dc	b'11010111 11111111'
	dc	b'01010101 01010111'
	dc	b'11111111 11111111'

	dc	b'11110101 01011111'		  [
	dc	b'11110101 11111111'
	dc	b'11110101 11111111'
	dc	b'11110101 11111111'
	dc	b'11110101 11111111'
	dc	b'11110101 11111111'
	dc	b'11110101 01011111'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  \
	dc	b'01011111 11111111'
	dc	b'11010111 11111111'
	dc	b'11110101 11111111'
	dc	b'11111101 01111111'
	dc	b'11111111 01011111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'

	dc	b'11010101 01111111'		  ]
	dc	b'11111101 01111111'
	dc	b'11111101 01111111'
	dc	b'11111101 01111111'
	dc	b'11111101 01111111'
	dc	b'11111101 01111111'
	dc	b'11010101 01111111'
	dc	b'11111111 11111111'

	dc	b'11110000 00001111'		  ^
	dc	b'11000011 11000011'
	dc	b'11000011 11111111'
	dc	b'00000000 00001111'
	dc	b'11000011 00001111'
	dc	b'11000011 00001111'
	dc	b'11000011 00000011'
	dc	b'11111111 11111111'

	dc	b'11110000 00001111'		  _
	dc	b'11000011 00000011'
	dc	b'11000011 00001111'
	dc	b'00000000 00001111'
	dc	b'11000011 00001111'
	dc	b'11000011 00001111'
	dc	b'11000011 00000011'
	dc	b'11111111 11111111'

	dc	b'11110101 11111111'		  `
	dc	b'11110101 11111111'
	dc	b'11111101 01111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  a
	dc	b'11111111 11111111'
	dc	b'11010101 01011111'
	dc	b'11111111 11010111'
	dc	b'11010101 01010111'
	dc	b'01011111 11010111'
	dc	b'11010101 01010111'
	dc	b'11111111 11111111'

	dc	b'01011111 11111111'		  b
	dc	b'01011111 11111111'
	dc	b'01010101 01011111'
	dc	b'01011111 11010111'
	dc	b'01011111 11010111'
	dc	b'01011111 11010111'
	dc	b'01010101 01011111'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  c
	dc	b'11111111 11111111'
	dc	b'11010101 01010111'
	dc	b'01011111 11111111'
	dc	b'01011111 11111111'
	dc	b'01011111 11111111'
	dc	b'11010101 01010111'
	dc	b'11111111 11111111'

	dc	b'11111111 11010111'		  d
	dc	b'11111111 11010111'
	dc	b'11010101 01010111'
	dc	b'01011111 11010111'
	dc	b'01011111 11010111'
	dc	b'01011111 11010111'
	dc	b'11010101 01010111'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  e
	dc	b'11111111 11111111'
	dc	b'11010101 01011111'
	dc	b'01011111 11010111'
	dc	b'01010101 01010111'
	dc	b'01011111 11111111'
	dc	b'11010101 01010111'
	dc	b'11111111 11111111'

	dc	b'11110101 01011111'		  f
	dc	b'11010111 11010111'
	dc	b'11010111 11111111'
	dc	b'01010101 01111111'
	dc	b'11010111 11111111'
	dc	b'11010111 11111111'
	dc	b'11010111 11111111'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  g
	dc	b'11111111 11111111'
	dc	b'11010101 01011111'
	dc	b'01011111 11010111'
	dc	b'01011111 11010111'
	dc	b'11010101 01010111'
	dc	b'11111111 11010111'
	dc	b'11010101 01011111'

	dc	b'01011111 11111111'		  h
	dc	b'01011111 11111111'
	dc	b'01010101 01011111'
	dc	b'01011111 11010111'
	dc	b'01011111 11010111'
	dc	b'01011111 11010111'
	dc	b'01011111 11010111'
	dc	b'11111111 11111111'

	dc	b'11110101 11111111'		  i
	dc	b'11111111 11111111'
	dc	b'11010101 11111111'
	dc	b'11110101 11111111'
	dc	b'11110101 11111111'
	dc	b'11110101 11111111'
	dc	b'11010101 01111111'
	dc	b'11111111 11111111'

	dc	b'11111111 01011111'		  j
	dc	b'11111111 11111111'
	dc	b'11111101 01011111'
	dc	b'11111111 01011111'
	dc	b'11111111 01011111'
	dc	b'11111111 01011111'
	dc	b'11010111 01011111'
	dc	b'11110101 01111111'

	dc	b'01011111 11111111'		  k
	dc	b'01011111 11111111'
	dc	b'01011111 01011111'
	dc	b'01011101 01111111'
	dc	b'01010101 11111111'
	dc	b'01011101 01111111'
	dc	b'01011111 01011111'
	dc	b'11111111 11111111'

	dc	b'11010101 11111111'		  l
	dc	b'11110101 11111111'
	dc	b'11110101 11111111'
	dc	b'11110101 11111111'
	dc	b'11110101 11111111'
	dc	b'11110101 11111111'
	dc	b'11010101 01111111'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  m
	dc	b'11111111 11111111'
	dc	b'01011111 11010111'
	dc	b'01010111 01010111'
	dc	b'01011101 11010111'
	dc	b'01011111 11010111'
	dc	b'01011111 11010111'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  n
	dc	b'11111111 11111111'
	dc	b'01010101 01011111'
	dc	b'01011111 11010111'
	dc	b'01011111 11010111'
	dc	b'01011111 11010111'
	dc	b'01011111 11010111'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  o
	dc	b'11111111 11111111'
	dc	b'11010101 01011111'
	dc	b'01011111 11010111'
	dc	b'01011111 11010111'
	dc	b'01011111 11010111'
	dc	b'11010101 01011111'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  p
	dc	b'11111111 11111111'
	dc	b'01010101 01011111'
	dc	b'01011111 11010111'
	dc	b'01011111 11010111'
	dc	b'01010101 01011111'
	dc	b'01011111 11111111'
	dc	b'01011111 11111111'

	dc	b'11111111 11111111'		  q
	dc	b'11111111 11111111'
	dc	b'11010101 01010111'
	dc	b'01011111 11010111'
	dc	b'01011111 11010111'
	dc	b'11010101 01010111'
	dc	b'11111111 11010111'
	dc	b'11111111 11010111'

	dc	b'11111111 11111111'		  r
	dc	b'11111111 11111111'
	dc	b'01110101 01011111'
	dc	b'01011111 11010111'
	dc	b'01011111 11111111'
	dc	b'01011111 11111111'
	dc	b'01011111 11111111'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  s
	dc	b'11111111 11111111'
	dc	b'11010101 01010111'
	dc	b'01011111 11111111'
	dc	b'11010101 01011111'
	dc	b'11111111 11010111'
	dc	b'01010101 01011111'
	dc	b'11111111 11111111'

	dc	b'11110101 11111111'		  t
	dc	b'11110101 11111111'
	dc	b'01010101 01011111'
	dc	b'11110101 11111111'
	dc	b'11110101 11111111'
	dc	b'11110101 11010111'
	dc	b'11111101 01011111'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  u
	dc	b'11111111 11111111'
	dc	b'01011111 11010111'
	dc	b'01011111 11010111'
	dc	b'01011111 11010111'
	dc	b'01011111 11010111'
	dc	b'11010101 01011111'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  v
	dc	b'11111111 11111111'
	dc	b'01011111 11010111'
	dc	b'01011111 11010111'
	dc	b'01011111 11010111'
	dc	b'11010111 01011111'
	dc	b'11110101 01111111'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  w
	dc	b'11111111 11111111'
	dc	b'01011111 11010111'
	dc	b'01011111 11010111'
	dc	b'01011101 11010111'
	dc	b'01010111 01010111'
	dc	b'01011111 11010111'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  x
	dc	b'11111111 11111111'
	dc	b'01011111 11010111'
	dc	b'11010111 01011111'
	dc	b'11110101 01111111'
	dc	b'11010111 01011111'
	dc	b'01011111 11010111'
	dc	b'11111111 11111111'

	dc	b'11111111 11111111'		  y
	dc	b'11111111 11111111'
	dc	b'01011111 11010111'
	dc	b'01011111 11010111'
	dc	b'01011111 11010111'
	dc	b'11010101 01010111'
	dc	b'11111111 11010111'
	dc	b'11010101 01011111'

	dc	b'11111111 11111111'		  z
	dc	b'11111111 11111111'
	dc	b'01010101 01010111'
	dc	b'11111111 01011111'
	dc	b'11110101 01111111'
	dc	b'11010111 11111111'
	dc	b'01010101 01010111'
	dc	b'11111111 11111111'

	dc	b'11111101 01011111'		  {
	dc	b'11110101 11111111'
	dc	b'11110101 11111111'
	dc	b'11010111 11111111'
	dc	b'11110101 11111111'
	dc	b'11110101 11111111'
	dc	b'11111101 01011111'
	dc	b'11111111 11111111'

	dc	b'11111101 01111111'		  |
	dc	b'11111101 01111111'
	dc	b'11111101 01111111'
	dc	b'11111101 01111111'
	dc	b'11111101 01111111'
	dc	b'11111101 01111111'
	dc	b'11111101 01111111'
	dc	b'11111101 01111111'

	dc	b'11010101 11111111'		  }
	dc	b'11111101 01111111'
	dc	b'11111101 01111111'
	dc	b'11111111 01011111'
	dc	b'11111101 01111111'
	dc	b'11111101 01111111'
	dc	b'11010101 11111111'
	dc	b'11111111 11111111'

	dc	b'11110101 11110111'		  ~
	dc	b'01011101 11010111'
	dc	b'01111101 01111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'

	dc	b'01110111 01110111'		  rub
	dc	b'11011101 11011101'
	dc	b'01110111 01110111'
	dc	b'11011101 11011101'
	dc	b'01110111 01110111'
	dc	b'11011101 11011101'
	dc	b'01110111 01110111'
	dc	b'11011101 11011101'

	end

TabData	privdata

iconRc	dc	i1'$80'	info about the object to draw
	dc	i1'0'
iconAddr dc	a4'icons'
	dc	i'2'
iRec	dc	i'0,0,5,8'

icons	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111100 00111111'
	dc	b'11111100 00111111'

	dc	b'11111111 00111111'
	dc	b'11111111 00111111'
	dc	b'11111111 00111111'
	dc	b'11111111 00111111'
	dc	b'11111111 00111111'

	dc	b'11111100 00111111'
	dc	b'11110011 11001111'
	dc	b'11111111 00111111'
	dc	b'11111100 11111111'
	dc	b'11110000 00001111'

	dc	b'11110000 00001111'
	dc	b'11111111 00111111'
	dc	b'11111100 00111111'
	dc	b'11111111 11001111'
	dc	b'11110000 00111111'

	dc	b'11110011 11001111'
	dc	b'11110011 11001111'
	dc	b'11110000 00001111'
	dc	b'11111111 11001111'
	dc	b'11111111 11001111'

	dc	b'11111100 00001111'
	dc	b'11111100 11111111'
	dc	b'11111100 00111111'
	dc	b'11111111 11001111'
	dc	b'11111100 00111111'

	dc	b'11111100 00111111'
	dc	b'11110011 11111111'
	dc	b'11110000 00111111'
	dc	b'11110011 11001111'
	dc	b'11111100 00111111'

	dc	b'11110000 00001111'
	dc	b'11111111 11001111'
	dc	b'11111111 00111111'
	dc	b'11111100 11111111'
	dc	b'11110011 11111111'

	dc	b'11111100 00111111'
	dc	b'11110011 11001111'
	dc	b'11111100 00111111'
	dc	b'11110011 11001111'
	dc	b'11111100 00111111'

	dc	b'11111100 00111111'
	dc	b'11110011 11001111'
	dc	b'11111100 00001111'
	dc	b'11111111 11001111'
	dc	b'11111100 00111111'

	dc	b'11001111 00001111'
	dc	b'11001100 11110011'
	dc	b'11001100 11110011'
	dc	b'11001100 11110011'
	dc	b'11001111 00001111'

	dc	b'11111100 11001111'
	dc	b'11111100 11001111'
	dc	b'11111100 11001111'
	dc	b'11111100 11001111'
	dc	b'11111100 11001111'

	dc	b'11001111 00001111'
	dc	b'11001100 11110011'
	dc	b'11001111 11001111'
	dc	b'11001111 00111111'
	dc	b'11001100 00000011'

	dc	b'11001100 00000011'
	dc	b'11001111 11110011'
	dc	b'11001111 11001111'
	dc	b'11001111 11110011'
	dc	b'11001100 00001111'

	dc	b'11001100 11110011'
	dc	b'11001100 11110011'
	dc	b'11001100 00000011'
	dc	b'11001111 11110011'
	dc	b'11001111 11110011'

	dc	b'11110011 00000011'
	dc	b'11110011 00111111'
	dc	b'11110011 00001111'
	dc	b'11110011 11110011'
	dc	b'11110011 00001111'

	dc	b'11001111 00001111'
	dc	b'11001100 11111111'
	dc	b'11001100 00001111'
	dc	b'11001100 11110011'
	dc	b'11001111 00001111'

	dc	b'11001100 00000011'
	dc	b'11001111 11110011'
	dc	b'11001111 11001111'
	dc	b'11001111 00111111'
	dc	b'11001100 11111111'

	dc	b'11001111 00001111'
	dc	b'11001100 11110011'
	dc	b'11001111 00001111'
	dc	b'11001100 11110011'
	dc	b'11001111 00001111'

	dc	b'11001111 00001111'
	dc	b'11001100 11110011'
	dc	b'11001111 00000011'
	dc	b'11001111 11110011'
	dc	b'11001111 00001111'

	dc	b'11001111 11000011'
	dc	b'00110011 00111100'
	dc	b'11110011 00111100'
	dc	b'11001111 00111100'
	dc	b'00000011 11000011'

	dc	b'11110000 11110011'
	dc	b'11001111 00110011'
	dc	b'11111100 11110011'
	dc	b'11110011 11110011'
	dc	b'11000000 00110011'

	dc	b'11001111 11001111'
	dc	b'00110011 00110011'
	dc	b'11110011 11110011'
	dc	b'11001111 11001111'
	dc	b'00000011 00000011'

	dc	b'11001111 00000000'
	dc	b'00110011 11111100'
	dc	b'11110011 11110011'
	dc	b'11001111 11111100'
	dc	b'00000011 00000011'

	dc	b'11001111 00111100'
	dc	b'00110011 00111100'
	dc	b'11110011 00000000'
	dc	b'11001111 11111100'
	dc	b'00000011 11111100'

	dc	b'11000011 11000000'
	dc	b'00111100 11001111'
	dc	b'11110011 11000011'
	dc	b'11001111 11111100'
	dc	b'00000000 11000011'

	dc	b'11111111 11111111'
	dc	b'11111111 00111111'
	dc	b'11111111 00111111'
	dc	b'11111111 00111111'
	dc	b'11111111 11111111'

	dc	b'11111100 00111111'
	dc	b'11110000 00001111'
	dc	b'11000000 00000011'
	dc	b'11111111 11111111'
	dc	b'00000000 00000000'

	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'11111111 11111111'
	dc	b'00000000 00000000'
	end
