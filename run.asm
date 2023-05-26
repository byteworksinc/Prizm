	mcopy run.macros
****************************************************************
*
*  CommonCOut - global data
*
****************************************************************
*
CommonCOut privdata
step	gequ	0	status enumerations
trace	gequ	1
go	gequ	2

chBuffSize equ 1024	size of the console character buffer
chBuffPtr ds	4	pointer to the character buffer
chBuffLen ds	2	# chars in the buffer

cursorDrawn ds	2	did we draw the cursor?
lastWasDelete ds 2	was the last character a delete?

p9DCB	dc	i'2,9',i4'0'	DCB for Get/Set prefix 9 calls

msg1	dc	i1'l:msg1a'
msg1a	dc	c'The prefix is invalid.  It',i1'13',c'was not changed.'

evRec	anop		event record
evWhat	ds	2
evMessage ds	4
evWhen	ds	4
evWhere	ds	4
evModifiers ds	2
;
;  Shared by StartConsole, StopConsole
;
patch2Len equ	31	length of the KeyOut patch

OldCOut	ds	4	original .CONSOLE COut vector
OldKeyIn	ds	4	original .CONSOLE KeyIn vector
OldWWChar ds	2	original jsr address for WriteOneChar
OldBytes	ds	5	original bytes just past OldCOut
OldPatch2 ds	patch2Len	original bytes from KeyIn patch

dnRec	dc	i'2'	GetDevNumber record
	dc	a4'cName'
dnDevnum	ds	2

cName	dc	i'l:cChars'
cChars	dc	c'.CONSOLE'

stRec	dc	i'5'	DStatus record
stDevnum	ds	2
	dc	i'$8007'
	dc	a4'stList'
	dc	i4'8'
	ds	4

stList	anop
COut	ds	4	character output vector
KeyIn	ds	4	character input vector
	end

****************************************************************
*
*  CheckForCommand - checks for menu command; waits for one if wait = true
*
*  Inputs:
*	X - wait flag
*
*  Notes:
*	called with a jsr, not a jsl
*
****************************************************************
*
CheckForCommand private

!			{see if we need to call Events}
	stz	done	if wait then begin
	txa		  done := false;
	bne	lb1	  getEvent := true;
!			  end {if}
!			else begin
!			  getEvent := false;
	lda	ourMenu	  if ourMenu then begin
	jeq	lb5
	inc	done	    done := true;
	pha		    if EventAvail($2A,lastEvent) then
	ph2	#$2A
	ph4	#lastEvent
	_EventAvail
	pla
	jeq	lb5
	lda	what	      getEvent :=
	cmp	#3		lastEvent.eventWhat in
	beq	lb1		[keyDownEvt,autoKeyEvt,mouseDownEvt];
	cmp	#5
	beq	lb1
	cmp	#1
	jne	lb5
!			    end; {if}
!			  end; {else}
!			if getEvent then begin
!			  {call Events}
!			  lastEvent.taskMask := $37FF;
lb1	anop		  repeat
	jsl	TestMouse	    if TestMouse then
	tax		      done := true
	bne	lb4
	lda	ourMenu	    else if ourMenu then begin
	beq	lb1
	pha		      fw := FrontWindow;
	pha
	_FrontWindow
	pha		      event :=
	ph2	#$76E	       TaskMaster($076E,lastEvent);
	ph4	#lastEvent
	_TaskMaster
	pl2	event
	pha		      if fw <> FrontWindow then
	pha
	_FrontWindow
	pla
	plx
	cmp	1,S
	bne	lb2
	txa
	cmp	3,S
	beq	lb3
lb2	pha			CheckWindow(FrontWindow);
	pha
	_FrontWindow
	jsl	CheckWindow
lb3	pla
	pla
	ph4	#lastEvent	      Events(lastEvent,event,done,true);
	ph2	event
	ph4	#done
	ph2	#1
	jsl	Events
!			      end; {else}
	lda	done	  until done;
	beq	lb1
lb4	ph4	grPtr	  StartDrawing(grPtr);
	_StartDrawing
!			  end; {if}
lb5	rts

done	ds	2	loop exit flag
event	ds	2	event code

lastEvent anop		event record
what	ds	2
message	ds	4
when	ds	4
where	ds	4
modifiers ds	2
taskData ds	4
taskMask dc	i4'$3DFF'
	end

****************************************************************
*
*  ConsoleCOut - Character output routine
*
****************************************************************
*
ConsoleCOut private
	using CommonCOut
	using BufferCommon
cleol	equ	$1D	clear to end of line key
delete	equ	$7F	DELETE key code
larrow	equ	08	non-destructive back space key code
lineFeed equ	10	line feed character
return	equ	13	RETURN key code
tab	equ	9	TAB key code
;
;  Write a character
;
write	phb		save user data bank
	phk		set local data bank
	plb
	php		use long registers
	long	I,M
	phx		save the caller's registers
	phy
	pha

	and	#$007F	make the input a character
	cmp	#' '	if erasing after a delete, ignore the
	bne	lb1	 write
	lda	lastWasDelete
	beq	lb1
	stz	lastWasDelete
	bra	wr3
lb1	sei		cannot interupt during buffer
	phd		 update!
	tax		place the char in the buffer
	ph4	chBuffPtr
	tsc
	tcd
	ldy	chBuffLen
	txa
	sta	[1],Y
	pla
	pla
	pld
	iny
	sty	chBuffLen
	lda	#10	update the heartbeat timer
	sta	InactiveCheck+4
	cpy	#chBuffSize-1	if the buffer is full then
	blt	wr2
	jsl	UpdateScreen2	  write the buffer to the screen
wr2	cli		allow interupts

wr3	pla		restore the caller's registers
	ply
	plx
	plp		restore the caller's register size
	plb		restore the caller's data bank
	rtl
	end

****************************************************************
*
*  ConsoleKeyAvail - See if a keypress is available
*
*  Outputs:
*	C - set if keypress available, else clear
*
****************************************************************
*
ConsoleKeyAvail private
	using CommonCOut
          
	ph2	#0
	ph2	#$0428
	ph4	#evRec
	_EventAvail
	pla
	cmp	#1
	bcs	lb1
	jsl	DrawCursor
	clc
lb1	rtl
	end

****************************************************************
*
*  ConsoleKeyIn - Character input routine
*
****************************************************************
*
ConsoleKeyIn private
	using CommonCOut
	using BufferCommon
;
;  Initialization
;
	phb		save user data bank
	phk		set local data bank
	plb
	php		use long registers
	long	I,M
	phx		save the caller's registers
	phy
;
;  Wait for a keypress event
;
	stz	lastWasDelete	clear the delete flag
lb1	ph2	#0	wait for a keypress
	ph2	#$0428
	ph4	#evRec
	_GetNextEvent
	pla
	beq	lb1
	lda	evMessage	handle special characters
	ldx	evModifiers
	jsr	SpecialChar
	bcs	lb1
	jsl	EraseCursor	erase the cursor, if any
;
;  Form the modifier/character return word
;
	lda	evMessage	get the keypress
	and	#$007F
	asl	evModifiers	test/set keyPad bit
	asl	evModifiers
	asl	evModifiers
	bcc	lb2
	ora	#$1000
lb2	asl	evModifiers	test/set controlKey bit
	bcc	lb3
	ora	#$0200
lb3	asl	evModifiers	test/set optionKey bit
	bcc	lb4
	ora	#$4000
lb4	asl	evModifiers	test/set capsLock bit
	bcc	lb5
	ora	#$0400
lb5	asl	evModifiers	test/set shiftKey bit
	bcc	lb6
	ora	#$0100
lb6	asl	evModifiers	test/set appleKey bit
	bcc	lb7
	ora	#$8000
lb7	ldx	evWhat	test/set repeat active bit
	cpx	#5
	bne	rt1
	ora	#$0800
;
;  Return the result
;
rt1	ply		restore the caller's registers
	plx
	plp		restore the caller's register size
	plb		restore the caller's data bank
	rtl
	end

****************************************************************
*
*  CopProcessor - process COP interupt
*
****************************************************************
*
CopProcessor private
	using InterceptCommon
	using	BufferCommon
stackDisp equ	14	disp to user's stack
addr	equ	11	pointer into cop memory area
dp	equ	2	caller's DP

	long	I,M	use long regs
	phx		save all registers
	phy
	pha
	phd
	phb
	phk
	plb
	tsc		set DP
	tcd
nn1	dec	addr	jump to proper COP handler
	lda	[addr]
	and	#$00FF
	inc	addr
	asl	a
	tax
	lda	CopVectors,X
	pha
	rts
;
;  Cop 2 - Auto-go line number
;
Cop2	ph2	lineNumber	MarkLine(lineNumber,' ');
	pea	' '
	jsl	MarkLine
	lda	[addr]	lineNumber := cop;
	sta	lineNumber
	ldx	#0	CheckForCommand(false)
	brl	lb4
;
;  Cop 1 - Break point.
;
Cop1	ph2	lineNumber	MarkLine(lineNumber,' ');
	pea	' '
	jsl	MarkLine
	lda	[addr]	lineNumber := cop;
	sta	lineNumber	MarkLine(lineNumber,stepChar);
	pha
	pea	stepChar
	jsl	MarkLine
	lda	#step	status := step;
	sta	status
	jsl	UpdateScreen2	UpdateScreen;
	_SysBeep	beep;
	bra	lb3	(Cop 0 does the rest)
;
;  Cop 0 - New line number
;
Cop0	clc		set stack address
	tsc
	adc	#stackDisp
	sta	regS
	lda	status	if status = go then
	cmp	#go
	bne	lb3
	ldx	#0	  CheckForCommand(false);
	brl	lb4	else begin
lb3	jsl	UpdateScreen2	  UpdateScreen;
	lda	#1	  set busy flag so we don't interupt
	sta	busy	   ourself
	ph2	disableScreenUpdates	  allow screen updates
	stz	disableScreenUpdates
	ph2	lineNumber	  MarkLine(lineNumber,' ');
	pea	' '
	jsl	MarkLine
	lda	[addr]	  lineNumber := cop;
	sta	lineNumber	  MarkLine(lineNumber,stepChar);
	pha
	pea	stepChar
	jsl	MarkLine
	lda	vrPtr	  update the debug screens
	ora	vrPtr+2
	beq	ds1
	ph4	vrPtr
	_StartDrawing
	ph2	#0
	jsl	DrawVariables
ds1	ph4	grPtr
	_StartDrawing
	pl2	disableScreenUpdates	  restore previous update status
	ldx	#0	  CheckForCommand(status <> trace);
	lda	status	  end;
	cmp	#trace
	beq	lb4
	inx
lb4	add2	addr,#2	skip line number
	phx
	lda	stepThru	if stepThru and returnCount = 0 then
	beq	lb5	  begin
	lda	returnCount
	bne	lb5
	stz	stepOnReturn	  stepOnReturn := false;
	stz	stepThru	  stepThru := false;
	lda	#step	  status := step;
	sta	status	  end;

lb5	cli		allow interupts
	lda	ourMenu	if the application menu bar is active
	bne	lb7	  then
lb6	jsl	TestMouse	  check for switch
	lsr	a
	plx
	bcs	lb8	  exit if mouse in step
	txa
	beq	lb8	  exit if not waiting for event
	phx
	bra	lb6
lb7	plx
	jsr	CheckForCommand	make the call
lb8	brl	exit2
;
;  Cop 3 - Entry to a subroutine
;
Cop3	lda	profile	if profile then
	beq	c3_1
	ldy	#2	  ProfileCall(cop^);
	lda	[addr],Y
	pha
	lda	[addr]
	pha
	jsl	ProfileCall
c3_1	lda	[addr]	save the addr of the name
	sta	procName	 for the variables window
	ldy	#2
	lda	[addr],Y
	sta	procName+2
	add2	addr,#4	skip the address
	inc	returnCount	returnCount := returnCount+1
	jsl	SaveFileName	save the file name
	brl	exit
;
;  Cop 4 - Exit from a subroutine
;
Cop4	lda	profile	if profile then
	beq	c4_1
	jsl	ProfileReturn	  ProfileReturn;
c4_1	jsl	RestoreFileName	restore the old file name
	jsl	RemoveProc	remove top variable list entry
	lda	stepOnReturn	if stepOnReturn then
	jeq	exit
	dec	returnCount	  returnCount -= 1
	bne	exit
	lda	#step	  if returnCount = 0 then begin
	sta	status	    status := step;
	lda	stepThru	    if not stepThru then
	bne	exit
	stz	stepOnReturn	      stepOnReturn := false;
	bra	exit
;
;  Cop 5 - Debugger symbol table
;
Cop5	ph4	procName	record the entry
	lda	[addr]
	pha
	ph2	addr+2
	lda	addr
	inc	a 
	inc	a
	pha
	ph2	DP
	jsl	AddProc
	lda	[addr]	skip the symbol table
	clc
	adc	#2
	adc	addr
	sta	addr
	bcc	c5_1
	inc	addr+2
c5_1	bra	exit
;
;  Cop 6 - Set File Name
;
Cop6	ldy	#2	find the source file
	lda	[addr],Y
	pha
	lda	[addr]
	pha
	jsl	PStringToOSString
	phx
	pha
	jsl	SetSourceWindow
	add2	addr,#4	skip the address
	bra	exit
;
;  Cop 7 - Debugger message
;
Cop7	lda	[addr]	skip the message
	clc
	adc	addr
	sta	addr
	bra	exit
;
;  Cop 8 - Global debugger symbol table
;
Cop8	lda	[addr]	record the entry
	pha
	ph2	addr+2
	lda	addr
	inc	a 
	inc	a
	pha
	jsl	AddGlobals
	lda	[addr]	skip the symbol table
	clc
	adc	#2
	adc	addr
	sta	addr
	bcc	c8_1
	inc	addr+2
c8_1	anop
;
;  General exit handler
;
exit	stz	busy	allow our interupts
exit2	plb		restore user registers
	pld
	pla
	ply
	plx
	rti

CopVectors dc	a'Cop0-1,Cop1-1,Cop2-1,Cop3-1,Cop4-1,Cop5-1,Cop6-1,Cop7-1,Cop8-1'
procName ds	4	addr of last proc name
	end

****************************************************************
*
*  DoVariables - Open or bring the variables window to front
*
****************************************************************
*
DoVariables start
dataH	equ	50	height of data area; 8* # of lines
dataW	equ	265	width of data area; 8* # chars + 25
infoHeight equ 12	height of info bar

!			{initialize the variables window}
	lda	vrPtr	if vrPtr = nil then begin
	ora	vrPtr+2
	jne	lb1
	stz	vrHeaderChanged	  vrHeaderChanged := false;
	pha		  vrPtr := NewWindow(myWindowDef);
	pha
	ph4	#myWindowDef
	_NewWindow
	jcs	Fail
	pl4	vrPtr
	ph4	vrPtr	  SelectWindow(vrPtr);
	_SelectWindow
	ph4	vrPtr	  StartDrawing(vrPtr);
	_StartDrawing
	ph4	vrPtr	  CreateSpecialControls(vrPtr,vrGrow,
	ph4	#vrGrow	    vrVScroll,0,20,10);
	ph4	#vrVScroll
	ph2	#0
	ph2	#20
	ph2	#10
	jsl	CreateSpecialControls
	ph4	#UpdateVrWindow	  SetContentDraw(@UpdateVrWindow,vrPtr);
	ph4	vrPtr
	_SetContentDraw
	ph4	#r	  StartInfoDrawing(r,vrPtr);
	ph4	vrPtr
	_StartInfoDrawing
	ph4	#r	  VrInfo(r,0,vrPtr);
	ph4	#0
	ph4	vrPtr
	jsl	VrInfo
	_EndInfoDrawing	  EndInfoDrawing;
	rtl		  end {if}
lb1	anop		else begin
!			  {if the window exists, select it}
	ph4	vrPtr	  SelectWindow(vrPtr);
	_SelectWindow
	ph4	vrPtr	  CheckWindow(vrPtr);
	jsl	CheckWindow
	rtl		  end; {else}

Fail	pla		flag an out of memory error
	pla
	jml	OutOfMemory

r	ds	8	work rectangle
myWindowDef anop	memory window definition
	dc	i'78'	paramLength
	dc	i'$C2B4'	wFrame
	dc	a4'title'	wTitle
	dc	i4'0'	wRefCon
	dc	i'0,0,0,0'	wZoom
	dc	a4'0'	wColor
	dc	i'0,0'	wYOrigin,wXOrigin
	dc	i'dataH,dataW'	wDataH,wDataW
	dc	i'0,0'	wMaxH,wMaxW
	dc	i'0,0'	wScrollVer,wScrollHor
	dc	i'0,0'	wPageVer,wPageHor
	dc	i4'0'	wInfoRefCon
	dc	i'infoHeight'	wInfoHeight
	dc	a4'0,VrInfo,0'	wFrameDefProc,wInfoDefProc,wContDefProc
	dc	i'100-dataH/2'	wPosition
	dc	i'320-dataW/2,100+dataH/2,320+dataW/2'
	dc	a4'-1'	wPlane
	dc	a4'0'	wStorage

title	dw	'Variables'
	end

****************************************************************
*
*  DrawCursor - if the cursor hasn't been drawn, draw it
*
*  Inputs:
*	cursorDrawn - has the cursor been drawn?
*
*  Outputs:
*	cursorDrawn - true
*
****************************************************************
*
DrawCursor start
	using CommonCOut
	using BufferCommon

         phb
	phk
	plb

	lda	cursorDrawn	if not cursorDrawn then
	bne	dc1
	jsl	UpdateScreen2	  take care of old actions
	ph4	shellWindow	  get the correct window
	jsl	FindActiveFile
	ph4	currentFile+wPtr
	_StartDrawing
	jsl	FollowCursor	  find the cursor
	ph2	currentFile+insert	  get the screen ready
	ph2	disableScreenUpdates
	stz	currentFile+insert
	stz	disableScreenUpdates
	jsr	DrawSpecialCursor	  draw the cursor
	ph4	grPtr
	_StartDrawing
	pl2	disableScreenUpdates	  restore the old settings
	pl2	currentFile+insert
	inc	cursorDrawn	  cursorDrawn = true
dc1	anop		endif

	plb
	rtl
	end

****************************************************************
*
*  DrawIcons - draws the step and switch icons on the menu bar
*
****************************************************************
*
DrawIcons private

	_HideCursor
	ldx	#144+320
	ldy	#0
lb1	lda	icons,Y
	sta	$E12000,X
	lda	icons+2,Y
	sta	$E12002,X
	lda	icons+4,Y
	sta	$E12004,X
	lda	icons+6,Y
	sta	$E12006,X
	lda	icons+8,Y
	sta	$E12008,X
	lda	icons+10,Y
	sta	$E1200A,X
	lda	icons+12,Y
	sta	$E1200C,X
	lda	icons+14,Y
	sta	$E1200E,X
	txa
	clc
	adc	#160
	tax
	tya
	adc	#16
	tay
	cpy	#16*9
	bne	lb1
	_ShowCursor
	rts

icons	dc	h'FFFFFFC003FFFFFF FFFFF0FFFF0FFFFC'
	dc	h'FFFFFF0000FFFFFF FFFF00FFFF00FFFC'
	dc	h'FFFFFC00003FFFFF FFF000FFFF000FFC'
	dc	h'FFFFFFC0003FFFFF FF000003C00000FC'
	dc	h'FFFFFFF0003FFFFF F0000003C000000C'
	dc	h'FFFFFFFFFFFFFFFF FF000003C00000FC'
	dc	h'FFFFFFC0003FFFFF FFF000FFFF000FFC'
	dc	h'FFFFFFC0003FFFFF FFFF00FFFF00FFFC'
	dc	h'FFFFFFF000FFFFFF FFFFF0FFFF0FFFFC'
	end

****************************************************************
*
*  DrawSpecialCursor - draw the cursor for the line input routine
*
*  Notes:
*	call this routine with a jsr
*
****************************************************************
*
DrawSpecialCursor private
	using BufferCommon

	lda	currentFile+cursorRow	set up the dest. rectangle
	asl	a
	asl	a
	asl	a
	inc	a
	sta	rect
	clc
	adc	#8
	sta	rect+4
	lda	currentFile+cursorColumn
	sec
	sbc	currentFile+leftColumn
	cmp	currentFile+width
	bge	rts
	inc	a
	asl	a
	asl	a
	asl	a
	sta	rect+2
	clc
	adc	#8
	sta	rect+6
	ph4	#rect
	_InvertRect
rts	rts

rect	ds	8
	end

****************************************************************
*
*  EraseCursor - if the cursor has been drawn, erase it
*
*  Inputs:
*	cursorDrawn - has the cursor been drawn?
*
*  Outputs:
*	cursorDrawn - false
*
****************************************************************
*
EraseCursor start
	using CommonCOut
	using BufferCommon

	phb
	phk
	plb

	lda	cursorDrawn	if cursorDrawn then
	beq	cd1
	jsl	UpdateScreen2	  take care of old actions
	ph4	shellWindow	  get the correct window
	jsl	FindActiveFile
	ph4	currentFile+wPtr
	_StartDrawing
	jsl	FollowCursor	  find the cursor
	ph2	currentFile+insert	  get the screen ready
	ph2	disableScreenUpdates
	stz	currentFile+insert
	stz	disableScreenUpdates
	ph2	currentFile+cursorRow	  erase the cursor
	jsl	DrawLine
	pl2	disableScreenUpdates	  restore the old settings
	pl2	currentFile+insert
	stz	cursorDrawn	  cursorDrawn = false
cd1	anop		endif

	plb
	rtl
	end

****************************************************************
*
*  ExecuteSelection - execute the current selection or line
*
****************************************************************
*
ExecuteSelection start
	using BufferCommon
cHand	equ	0	handle of the character buffer
size	equ	4	size of the buffer
sPtr	equ	8	work pointer; start of buffer-1

lSelect	equ	12	local working copy of select
lCursor	equ	16	local working copy of cursor

	subroutine ,20

	_WaitCursor	{this takes time...}
	SetGS	stDCB	{set the exit variable}
!			{use the current window for output}
	move4 currentFile+wPtr,shellWindow shellWindow := currentFile.wPtr;
!			{compact the buffer (prep. for select)}
	jsl	Compact	Compact;
!			with currentFile do begin
!			  {if no selection, select the line}
	lda	currentFile+selection	  if not selection then begin
	bne	lb5
	move4 currentFile+cursor,lSelect   select := cursor;
	ldy	#0	    while select^ <> return do
	short M
	lda	#RETURN
lb1	cmp	[lSelect],Y
	beq	lb2
	iny		      select := pointer(ord4(select)+1);
	bra	lb1
lb2	iny		    select := pointer(ord4(select)+1);
	long	M
	tya
	clc
	adc	lSelect
	sta	currentFile+select
	lda	lSelect+2
	adc	#0
	sta	currentFile+select+2
	sub4	currentFile+buffStart,#1,sPtr sPtr := pointer(ord4(buffStart)-1);
	move4 currentFile+cursor,lCursor   repeat
lb3	dec4	lCursor	      cursor := pointer(ord4(cursor)-1);
	cmpl	lCursor,sPtr	    until (cursor = sPtr)
	beq	lb4	      or (cursor^ = return);
	lda	[lCursor]
	and	#$00FF
	cmp	#RETURN
	bne	lb3
lb4	add4	lCursor,#1,currentFile+cursor cursor := pointer(ord4(cursor)+1);
	bra	lb6	    end {if}
!			  else if ord4(cursor) > ord4(select)
lb5	cmpl	currentFile+cursor,currentFile+select
	blt	lb6	    then begin
!	lda	currentFile+cursor	    {make sure cursor < select}
	ldx	currentFile+select	    sPtr := cursor;
	sta	currentFile+select	    cursor := select;
	stx	currentFile+cursor	    select := sPtr;
	lda	currentFile+cursor+2
	ldx	currentFile+select+2
	sta	currentFile+select+2
	stx	currentFile+cursor+2
	jsl	FindCursor
!			    end; {else}
!			  {insure that last char is return}
!			  size := ord4(select)-ord4(cursor);
lb6	sub4	currentFile+select,currentFile+cursor,size
	sub4	currentFile+select,#1,sPtr sPtr := pointer(ord4(select)-1);
	lda	[sPtr]	  if sPtr^ <> return then
	and	#$00FF
	cmp	#RETURN
	beq	lb7
	inc4	size	    size := size+1;
lb7	anop		  {get a buffer}
	pha		  cHand := pointer(NewHandle(size+1,
	pha		    UserID,$C000,nil));
	ldx	size+2
	lda	size
	inc	a
	bne	lb8
	inx
lb8	phx
	pha
	ph2	#~User_ID
	ph2	#$C000
	ph4	#0
	_NewHandle
	pl4	cHand
	bcc	lb9	  if ToolError <> 0 then begin
	jsl	OutOfMemory	    OutOfMemeory;
	jsl	Expand	    Expand;
	brl	lb10	    end {if}
lb9	anop		  else begin
!			    {move in the text to execute}
	ph4	currentFile+cursor	    MoveBack(cursor,cHand^,size);
	ldy	#2
	lda	[cHand],Y
	pha
	lda	[cHand]
	pha
	ph4	size
	jsl	MoveBack
	clc		    sPtr := pointer(ord4(cHand^)+size);
	lda	size
	adc	[cHand]
	sta	sPtr
	ldy	#2
	lda	size+2
	adc	[cHand],Y
	sta	sPtr+2
	dec4	sPtr	    sPtr^ := 0;
	lda	#$000D	    sPtr := pointer(ord4(sPtr)-1);
	sta	[sPtr]	    sPtr^ := return;
!			    {expand the buffer}
	jsl	Expand	    Expand;
!			    {get rid of selection}
	stz	currentFile+selection	    selection := false;
!			    {move to start of next line}
!			    cursor := pointer(ord4(select)-1);
	sub4	currentFile+select,#1,currentFile+cursor
	jsl	FindCursor	    FindCursor;
	ph2	currentFile+insert	    oldInsert := insert;
!			    {new text must be inserted!}
	lda	#1	    insert := true;
	sta	currentFile+insert
	pea	RETURN	    Key(chr(return));
	jsl	Key
!			    {execute the commands}
!			    exDCB.flag := $8000;
	ldy	#2	    exDCB.commandString := cHand^;
	lda	[cHand]
	sta	commandString
	lda	[cHand],Y
	sta	commandString+2
	stz	sourcePtr	    sourcePtr := nil;
	stz	sourcePtr+2
	jsl	StartConsole	    StartConsole;
	jsl	InstallIntercepts	    install the tool intercepts
	tsc		    save registers for abort
	sta	SReg
	tdc
	sta	DReg
	ExecuteGS exDCB	    ORCAExecuteGS(exDCB);
Abort2	jsl	StopConsole	    StopConsole;
	jsl	RemoveIntercepts	    remove the tool intercepts
!			    {restore insert flag}
	pl2	currentFile+insert	    insert := oldInsert;
!			    {get rid of buffer}
	ph4	cHand	    DisposeHandle(pointer(cHand));
	_DisposeHandle
!			    end; {else}
!			  end; {with}
lb10	jsl	ResetCursor	ResetCursor;
	return
;
;  Abort - entry point for an aborted EXEC file
;
Abort	entry
	phk
	plb
	rep	#$FF
	lda	SReg
	tcs
	lda	DReg
	tcd
	bra	Abort2
;
;  Local data
;
SReg	ds	2	stack reg for abort
DReg	ds	2	DP reg for abort

exDCB	dc	i'2'	ORCAExecute DCB
flag	dc	i'$8000'
commandString ds 4

stDCB	dc	i'3'	ORCA SetDCB DCB
	dc	a4'exit'
	dc	a4'on'
	dc	i'0'
exit	dosw	Exit
on	dosw	On
	end

****************************************************************
*
*  GetHandleID - get the user ID for a handle
*
*  Inputs:
*	hand - handle
*
*  Outputs:
*	A - user ID
*
****************************************************************
*
GetHandleID private
hand	equ	5	direct page disp to the handle

	phd
	tsc
	tcd
	ldy	#6
	lda	[hand],Y
	pld
	plx
	ply
	ply
	phx
	rts
	end

****************************************************************
*
*  InactiveCheck - check for inactivity
*
*  Inputs:
*	chBuffPtr - pointer to the character buffer
*	chBuffLen - number of characters in the character buffer
*
****************************************************************
*
InactiveCheck private
	using CommonCOut
	using BufferCommon

	ds	4	interupt header
	ds	2	counter
	dc	i'$A55A'	signature

UpdateScreen entry
	php		use long regs
	long	I,M
	phb
	phk
	plb
	lda	chBuffLen	skip if there are no new characters
	beq	lb6
	lda	#1	return on the next heartbeat if we
	sta	InactiveCheck+4	 have to quit early
	lda	busy	skip if we are doing stuff that should
	bne	lb6	 not be interupted
	stz	InactiveCheck+4
	ph2	disableScreenUpdates
	stz	disableScreenUpdates	enable screen updates
	ph4	shellWindow
	jsl	FindActiveFile
	tax
	beq	lb5
	ph4	shellWindow
	_StartDrawing
	ph2	#0	DoPaste(false,pointer(chBuffPtr),
	ph4	chBuffPtr	 chBuffLen);
	ph2	chBuffLen
	jsl	DoPaste
	jsl	DrawScreen	redraw the screen
	stz	chBuffLen	no chars in buffer...
	ph4	grPtr	set graphics port
	_StartDrawing
lb5	pl2	disableScreenUpdates	restore screen update flag
lb6	plb
	plp
	rtl
;
;  UpdateScreen2 - update the screen, even if busy
;
UpdateScreen2 entry
	ph2	busy
	stz	busy
	jsl	UpdateScreen
	pl2	busy
	rtl
	end

****************************************************************
*
*  InitRun - Variable initialization for the Run unit
*
*  Note:
*	The module is not restartable, so 0 values are not
*	specifically set
*
****************************************************************
*
InitRun	start
	using CommonCOut
dataW	equ	320	size of initial window
dataH	equ	85

!			{initialize the graphics window}
	lda	grPtr	if grPtr = nil then begin
	ora	grPtr
	bne	lb1
	pha		  grPtr := NewWindow(myWindowDef);
	pha
	ph4	#myWindowDef
	_NewWindow
	jcs	Fail
	pl4	grPtr
!			  {create the grow box}
	pha		  grGrow := NewControl(grPtr,r,nil,0,0,
	pha		    0,0,pointer($08000000),0,nil);
	ph4	grPtr
	ph4	#r
	lda	#0
	pha
	pha
	pha
	pha
	pha
	pha
	pea	$0800
	pha
	pha
	pha
	pha
	pha
	_NewControl
	bcs	Fail
	pl4	grGrow
!			  end; {if}
lb1	anop		if not initialized then begin
	ph4	#260	  <record prefix 9>
	jsl	~New
	phx
	pha
	phd
	tsc
	tcd
	lda	#260
	sta	[3]
	pld
	pl4	p9DCB+4
	GetPrefixGS p9DCB	  <record prefix 9>
!			  {initialize true flags}
	lda	#1	  compileLink := true;
	sta	compileLink
	sta	compileDebug	  compileDebug := true;
	sta	linkExecute	  linkExecute := true;
	sta	linkSave	  linkSave := true;
	sta	gsosAware	  gsosAware := true;
	stz	messageAware	  messageAware := false;
	stz	deskAware	  deskAware := false;
!			  {no templates}
	stz	templateList	  templateList := true;
	stz	templateList+2
!			  {set up execute options}
	lda	#go	  excuteMode := go;
	sta	executeMode
	stz	executeCommandLine	  executeCommandLine := '';
	stz	commandLine	  commandLine := '';
!			  {initialize the stack pointers}
	lda	#$2000	  regS := $2000;
	sta	regS
!			  {set up the console output buffer
	ph4	#chBuffSize
	jsl	~New
	sta	chBuffPtr
	stx	chBuffPtr+2
	ora	chBuffPtr+2
	bne	lb2
	jsl	OutOfMemory
!			  {initialization complete}
lb2	lda	rtl	  initialized := true;
	sta	lb1
rtl	rtl		  end; {if}

Fail	pla
	pla
	stz	grGrow
	stz	grGrow+2
	jml	OutOfMemory

r	dc	i'dataW-13,dataH-24,dataW+1,dataH+2' close box rect
myWindowDef anop	memory window definition
	dc	i'78'	paramLength
	dc	i'$C184'	wFrame
	dc	a4'title'	wTitle
	dc	i4'0'	wRefCon
	dc	i'25,0,200,640'	wZoom
	dc	a4'0'	wColor
	dc	i'0,0'	wYOrigin,wXOrigin
	dc	i'dataH,dataW'	wDataH,wDataW
	dc	i'0,0'	wMaxH,wMaxW
	dc	i'0,0'	wScrollVer,wScrollHor
	dc	i'0,0'	wPageVer,wPageHor
	dc	i4'0'	wInfoRefCon
	dc	i'0'	wInfoHeight
	dc	a4'0,0,UpdateGrWindow'	wFrameDefProc,wInfoDefProc,wContDefProc
	dc	i'200-dataH'	wPosition
	dc	i'640-dataW,200,640'
	dc	a4'0'	wPlane
	dc	a4'0'	wStorage

title	dw	'Graphics Output'
	end

****************************************************************
*
*  InstallIntercepts - Install tool box intercepts
*
****************************************************************
*
InstallIntercepts private
	using InterceptCommon
DrawMenuBar equ $2A0F	tool numbers of tool calls that get
EventAvail equ $0B06	 special handling
GetNextEvent equ $0A06
GetOSEvent equ $1606
LoadTools equ	$0E01
LoadOneTool equ $0F01
MMStartUp equ	$0202
OSEventAvail equ $1706
UnLoadOneTool equ $1001
PPToPort equ $D604

	php
	sei
	move4 $E10000,toolVector	save the old tool vector
	lda	#toolIntercept	set our local vector
	sta	$E10001
	lda	#>toolIntercept
	sta	$E10002
	plp
	stz	menuChanged	the menu bar has not been changed yet
	lda	#1	we are using our menu
	sta	ourMenu
	rtl
;
;  Run-time tool intercept routine
;
toolIntercept anop
	php		save the regs we need for the checks
	pha
	phy
	phb
	phk
	plb

	cpx	#LoadTools	branch to special handlers
	jeq	LoadToolsIntercept
	cpx	#PPToPort
	jeq	PPToPortIntercept
	cpx	#LoadOneTool
	jeq	LoadOneToolIntercept
	cpx	#UnLoadOneTool
	jeq	UnLoadOneToolIntercept
	cpx	#DrawMenuBar
	jeq	DrawMenuBarIntercept
	cpx	#MMStartUp
	jeq	MMStartUpIntercept
	cpx	#GetOSEvent
	beq	ti0
	cpx	#GetNextEvent
	beq	ti0
	cpx	#OSEventAvail
	beq	ti0
	cpx	#EventAvail
	bne	ti1
ti0	brl	GetEventIntercept

!			block dangerous calls
ti1	ldy	#1	ClearScreen
	cpx	#$1504
	jeq	in4
	iny		RefreshDeskTop
	cpx	#$390E
	jeq	in4
	cpx	#$0B04	GrafOff
	jeq	in5
	cpx	#$4B0E	SetSysWindow
	jeq	in4

	txa		branch if this is not a startup or
	and	#$FF00	 shutdown call
	cmp	#$0200
	beq	ti2
	cmp	#$0300
	bne	ti3
ti2	txa		branch if this tool is one of ours
	and	#$00FF
	jsr	OurTool
	bcs	in1
ti3	plb		this is not a call that needs to be
	ply		 intercepted -- proceed to the normal
	pla		 tool handler
	plp
	jml toolVector
;
;  Startup/Shutdown Intercept
;
;  We do not want the application to restart or shut down any
;  tools that we need.  This intercept removes any bytes placed
;  on the stack, and returns to the caller as if the action
;  were performed.
;
in1	cpx	#$020E	if this is a window manager startup then
	bne	wm1
	phx		  build a list of our windows
	phy
	jsl	NewWindowList
	bra	in1b
wm1	cpx	#$030E	else if it is a window manager shutdown
	bne	wm2	  then
	phx
	phy
	jsl	DisposeWindowList	  remove user windows
	bra	in1b
wm2	lda	menuChanged	branch if the menu bar has been saved	
	bne	in1a
	txa		  ...or if it's only SANE
	and	#$00FF
	cmp	#10
	beq	in1a
	phx		  save the call number
	phy		  save the disp into the tool table
	inc	menuChanged	  mark it as saved
	stz	ourMenu	  not using our menu
	pha		  get the system menu bar handle
	pha
	_GetSysBar
	pl4	sysMenuBar
	pha		  create a new, blank menu bar
	pha
	ph4	#0
	_NewMenuBar
	_SetSysBar
	ph4	#0
	_SetMenuBar
	pha		  draw it
	_FixMenuBar
	pla
	_HideCursor
	_DrawMenuBar
	_ShowCursor
in1b	ply		  recover the tool table disp
	plx		  recover the call number
in1a	txa		if this is a startup call then
	and	#$FF00
	cmp	#$0200
	bne	in2
	lda	tools+2,Y	  get the # of words on the stack
	bra	in3	else
in2	lda	tools+3,Y	  get # words for shutdown
in3	and	#$00FF	branch if none
	beq	in5
	tay		remove the spare words
in4	lda	8,S
	sta	10,S
	lda	6,S
	sta	8,S
	lda	4,S
	sta	6,S
	lda	2,S
	sta	4,S
	pla
	sta	1,S
	dey
	bne	in4
in5	plb		recover the user's regs
	ply
	pla
	plp
	lda	#0	set non-error return condition
	clc
	rtl		return to caller
;
;  LoadOneTool Intercept
;
;  We don't want the application to load any tools that we have
;  already loaded.  This intercept masks tool loads for our
;  tools.
;
LoadOneToolIntercept anop

	lda	12,S	get the tool number
	jsr	OurTool	see if it's ours
	jcc	ti3	no -> pass it on
	ldy	#2	yes -> remove the parms and trap the
	bra	in4	 call
;
;  UnLoadOneTool Intercept
;
;  We don't want the application to unload any tools that we need.
;  This intercept masks tool unloads for our tools.
;
UnLoadOneToolIntercept anop

	lda	10,S	get the tool number
	jsr	OurTool	see if it's ours
	jcc	ti3	no -> pass it on
	ldy	#1	yes -> remove the parms and trap the
	bra	in4	 call
;
;  LoadTools Intercpt
;
;  We do not want any of the RAM based tools we are using to be
;  reloaded from disk.  The intercept LoadOneTool can trap individual
;  loads.  This intercept scans the user's list, passing each load
;  on to LoadOneTool as an individual call.  The LoadOneTool intercept
;  routine will then mask any that are dangerous.
;
TTP	equ	16	tool table pointer
loop	equ	1	loop counter
err	ds	2	error code

LoadToolsIntercept anop
	phx		save X
	phd		save D
	pha		create work space
	tsc		set up DP
	tcd
	stz	err	no error so far
	lda	[TTP]	get the # of tools to load
	beq	lt2
	sta	loop
	add4	TTP,#2
lt1	lda	[TTP]	load a tool
	pha
	ldy	#2
	lda	[TTP],Y
	pha
	_LoadOneTool
	sta	err
	bcs	lt2
	add4	TTP,#4	next tool
	dec	loop
	bne	lt1
lt2	pla		remove work space
	pld		restore caller's regs
	plx
	plb
	ply
	pla
	plp
	lda	2,S	remove parm from stack
	sta	6,S
	pla
	sta	3,S
	pla
	sec		return error code
	lda	>err
	bne	lt3
	clc
lt3	rtl
;
;  OurTool - this common subroutine tests to see if the tool
;  being called is in the list of our tools.  The function
;  number is not tested in any way.  If it is one of our tools,
;  the carry flag is set and Y indexes into the tools array.
;
;  On entry, the tool number is in A
;
OurTool	ldy	#0	scan the tool table
ot1	cmp	tools,Y
	beq	ot2
	iny
	iny
	iny
	iny
	cpy	#toolEnd-tools
	bne	ot1
	clc		not found -> not one of ours
	rts

ot2	sec		found -> one of ours
	rts
;
;  DrawMenuBarIntercept - if the menu bar gets redrawn, we must
;  repaint the icons
;
DrawMenuBarIntercept anop
	jsl	toolVector	draw the menu bar
	jsr	DrawIcons	draw our icons
	brl	in5	return to caller
;
;  MMStartUpIntercept - we must return a user id to the application
;
MMStartUpIntercept anop
	pha
	pha
	lda	13,S
	and	#$00FF
	pha
	lda	13,S
	pha
	_FindHandle
	jsr	GetHandleID
	sta	10,S
	brl	in5
;
;  PPToPortIntercept - make sure the call uses 640 mode
;
PPToPortIntercept anop
	plb		get the junk off of the stack
	ply
	pla
	plp
	phb		use local addressing
	phk
	plb
	tsc		set up our stack frame
	phd
	tcd
	lda	[15]	see if it is 640 mode
	and	#$80
	bne	pp3
	ldy	#14	make a copy of the caller's locInfo
pp1	lda	[15],Y
	sta	liRec,Y
	dey
	dey
	bpl	pp1
	lda	liRec	adjust the SCB
	ora	#$0080
	sta	liRec
	asl	liRec+10	adjust boundsRect
	asl	liRec+14
	ldy	#6	make a copy of the caller's srcRect
pp2	lda	[11],Y
	sta	srcRect,Y
	dey
	dey
	bpl	pp2
	asl	srcRect+2	adjust srcRect
	asl	srcRect+6
	lla	11,srcRect	use our rect
	lla	15,liRec	use our locInfo
	asl	9	adjust caller's destX
pp3	pld		remove our stack frame
	plb
	ldx	#PPToPort
	jml toolVector	make the call

srcRect	ds	8
liRec	ds	16
;
;  GetEventIntercept - Handle all kinds of events, masking out
;  any mouse down events in the switcher icon, step icon,
;  or one of our windows.
;
GetEventIntercept anop
	stx	callNum	allow switch events
ge1	jsl	TestMouse
	pha		get the event
	lda	16,S
	pha
	ph4	#event
	ldx	callNum
	jsl	ToolVector
	php		save critical regs
	pha
	bcs	ge3

	lda	ourMenu	if this is not our menu then
	bne	ge3
	lda	what	  if this was a mouse down event then
	cmp	#1
	bne	ge3
	pha		    if it was in a window then
	ph4	#windowPtr
	ph2	where+2
	ph2	where
	_FindWindow
	pla
	beq	ge3
	lda	windowPtr
	ora	windowPtr+2
	beq	ge3
	ph4	windowPtr	      if it was our window then begin
	jsl	IsOurWindow
	tax
	beq	ge3
ge2	pha			wait for the mouse up
	ph2	#0
	_WaitMouseUp
	pla
	bne	ge2
	pla			get a new event
	plp
	pla
	bra	ge1		end;

ge3	phd		return the event to the user...
	tsc
	tcd
	ldy	#14	copy the event record
ei1	lda	event,Y
	sta	[17],Y
	dey
	dey
	bpl	ei1
	lda	6	copy the result
	sta	23
	lda	15	place the return addr next to the result
	sta	21
	lda	14
	sta	20
	lda	7	restore regs, fix stack
	sta	18
	lda	4
	sta	17
	lda	3
	sta	16
	lda	1
	sta	14
	tsc
	clc
	adc	#13
	tcs
	pld
	pla
	plp
	plb
	rtl

callNum	ds	2	type of event call
windowPtr ds	4	ptr to window where mouse down occurred

event	anop		event record
what	ds	2
message	ds	4
when	ds	4
where	ds	4
modifiers ds	2
	end

****************************************************************
*
*  InstallProfiler - Install the heartbeat portion of the profiler
*  RemoveProfile - Remove the profiler
*
****************************************************************
*
InstallProfiler start

	lda	#1
	sta	count
	ph4	#Profiler
	_SetHeartBeat
	rtl

RemoveProfiler entry
	ph4	#Profiler
	_DelHeartBeat
	rtl

Profiler ds	4
count	ds	2
	dc	i'$A55A'

	php		use long regs
	long	I,M
	phb
	phk
	plb
	lda	#1	make sure we get called again
	sta	count
	lda	subLink	if there is an entry then
	ora	subLink+2
	beq	lb1
	phd		  subLink^^ += 1
	ph4	subLink
	tsc
	tcd
	ldy	#2
	lda	[1],Y
	tax
	lda	[1]
	sta	1
	stx	3
	lda	[1]
	inc	a
	sta	[1]
	bne	lb0
	lda	[1],Y
	inc	a
	sta	[1],Y
lb0	pla
	pla
	pld
lb1	plb		restore entry status
	plp
	rtl
	end

****************************************************************
*
*  InterceptCommon - common area for tool intercepts
*
****************************************************************
*
InterceptCommon privdata
;
;  Common variables
;
appMenuBar ds	4	handle of application menu bar
menuChanged ds 2	has the menu bar been changed?
sysMenuBar ds	4	handle of our menu bar
toolVector ds	4	standard tool vector
;
;  Tool intercept table
;
tools	tool	1,0,0	Tool Locator
	tool	2,1,1	Memory Manager
	tool	4,4,0	QuickDraw II
	tool	5,0,0	Desk Manager
	tool	6,7,0	Event Manager
	tool	11,0,0	Integer Math Tool Set
	tool	14,1,0	Window Manager
	tool	15,2,0	Menu Manager
	tool	16,2,0	Control Manager
	tool	18,0,0	QuickDraw Aux
	tool	19,2,0	Print Manager
	tool	20,2,0	Line Edit
	tool	21,1,0	Dialog Manager
	tool	22,0,0	Scrap Manager
	tool	23,2,0	Standard File Manager
	tool	27,2,0	Font Manager
	tool	28,0,0	List Manager
	tool	10,1,0	SANE
	tool	30,1,0	Resource Manager
toolEnd	anop
	end

****************************************************************
*
*  LoadAndCall - Do an initial load (if needed) and call the module
*
*  Inputs:
*	name - pointer to the full path name of the module
*	restartable - can the application be restarted?
*
****************************************************************
*
LoadAndCall private
addr	equ	0	address of the executable program
handle	equ	4	handle for DP memory
tgrPtr	equ	8	temp storage for gr window
exeFileType equ 12

SYS	equ	$FF	file types
S16	equ	$B3
NDA	equ	$B8

	subroutine (4:namePtr,2:restartable,2:traceAllowed),14

	lda	#1	assume success
	sta	loadSucceeded
	move4 namePtr,giName	get the file type
	GetFileInfoGS giDCB
	jcs	loadError
	lda	giFileType
	sta	exeFileType
;
;  Handle system files
;
	cmp	#SYS	branch if this is not a system file
	beq	ss1
	cmp	#S16
	bne	nd1
ss1	jsl	RestorePrefix9	RestorePrefix9;
	ph4	#ORCA_TEMP	Sleep(@'9/PRIZM.TEMP');
	jsl	Sleep
	jsl	RemoveIntercepts	RemoveIntercepts
	jsl	StopConsole	StopConsole
	jsl	Expand	Expand
	ph2	#5	SetVector(5,oldVector5)
	ph4	oldVector5
	_SetVector
	ph2	#1	ShutDownTools(1, startStopParm)
	ph4	startStopParm
	_ShutDownTools
	jsr	~ShutDown	ShutDown; {shut down environment}
	move4 giName,pathname	Quit;
	QuitGS qtDCB

qtDCB	dc	i'2'	P16Quit DCB
pathname ds	4
	dc	i'0'
;
;  Handle NDA files
;
nd1	cmp	#NDA
	jne	ex1
	GetLevelGS lvRec	increment the GS/OS level
	inc	lvLevel
	SetLevelGS lvRec
	stz	restartable	not restartable
	sec		load the module
	tsc
	sbc	#10
	tcs
	ph2	#0
	ph4	namePtr
	ph2	#0
	ph2	#1
	_InitialLoad2
	jcs	lb2a
	pl2	applicationID	save for later dispose call
	pl4	addr	recover the entry point
	pla		no DP space allowed
	pla		no stack

	_QDAuxStartup	kick in the alternate menu bar
	jsl	NewWindowList	record the current windows
	php		save these for later restoration
	sei
	move4 $E100A8,oldE100A8
	move4 jml,$E100A8
	move4 $E100B0,oldE100B0
	move4 jmlB0,$E100B0
	plp
	phd
	phb
	tsc
	sta	myStack
	ldy	#12	do a StartDesk call
	lda	[addr],Y
	sta	jsl1+1
	sta	jsl2+1
	iny
	lda	[addr],Y
	sta	jsl1+2
	sta	jsl2+2
	lda	#1
jsl1	jsl	jsl1
	ldy	#1	open the desk accessory
	lda	[addr]
	sta	jsl3+1
	lda	[addr],Y
	sta	jsl3+2
	pha
	pha
jsl3	jsl	jsl3
	move4 grPtr,tgrPtr	save the current graphics window
	pl4	grPtr	use the window as the graphics window
	ph4	addr	call the action routine
	jsl	NDAAction
	move4 tgrPtr,grPtr	restore the main graphics window
	ldy	#4	do the close call
	lda	[addr],Y
	sta	jsl4+1
	iny
	lda	[addr],Y
	sta	jsl4+2
jsl4	jsl	jsl4
	lda	#0	do an EndDesk call
jsl2	jsl	jsl1
	brl	quitReturn	exit
;
;  Handle EXE files
;
ex1	php		set up an intercept for quit calls
	sei
	move4 $E100A8,oldE100A8
	move4 jml,$E100A8
	move4 $E100B0,oldE100B0
	move4 jmlB0,$E100B0
	plp
	pha		branch if the module is not in memory
	ph4	namePtr
	_GetUserID2
	pla
	bcs	lb1
	sta	applicationID
	sec		try to restart
	tsc
	sbc	#10
	tcs
	ph2	applicationID
	_Restart
	bcc	lb3
	bra	lb2	the restart failed - do initial load
lb1	sec		load the module
	tsc
	sta	loadStack
	sbc	#10
	tcs
lb2	ph2	#0
	ph4	namePtr
	ph2	#0
	ph2	#1
	_InitialLoad2
	bcc	lb3

lb2a	lda	loadStack	handle a loader error
	tcs
loadError ph2	#8
	ph2	#0
	jsl	FlagError
	stz	loadSucceeded
	brl	lb7

lb3	pl2	applicationID	get the user id
	pl4	addr	get the program address
	lda	3,s	if the bank zero memory asked for is 0,
	bne	lb3b	 give the program 4K
	lda	#4096
	sta	3,s
lb3b	pla		branch if specific bank zero memory
	bne	lb3a	 has been loaded already
	pha		allocate the bank zero memory
	pha
	pha
	lda	7,s
	pha
	ph2	applicationID
	ph2	#$C015
	ph4	#0
	_NewHandle
	pl4	handle	get the addr of the bank zero memory
	bcc	lb3c
	jsl	OutOfMemory
	brl	lb5a
lb3c	lda	[handle]
lb3a	sta	regD	set up the user's DP, S register values
	pla
	clc
	adc	regD
	dec	a
	sta	regS
	phd		save our DP
	phb		save our data bank
	tsc		save the current stack
	sta	myStack
	lda	regS	set user's stack
	tcs
	phk		set the return address
	ph2	#ReturnFromProgram-1
	tsc
	sta	regS

	lda	[namePtr]	set prefix 9 to the prog's prefix
	pha
	tay
	iny
	lda	#':'
sp1	cmp	[namePtr],Y
	beq	sp2
	dey
	bne	sp1
sp2	dey
	tya
	sta	[namePtr]
	long	I,M
	move4 namePtr,spName
	SetPrefixGS spDCB
	pla
	sta	[namePtr]
	GetLevelGS lvRec	increment the GS/OS level
	inc	lvLevel
	SetLevelGS lvRec

	short M	place the module's address on the stack
	lda	addr+2
	pha
	long	M
	lda	addr
	dec	a
	pha
	lda	regD	set up DP
	tcd
	lda	commandLine	if commandLine = '' then
	and	#$00FF
	bne	lb4a
	ldx	#0	  no command line
	txy
	bra	lb4b	else
lb4a	ldx	#^commandLine	  pass the CL address
	ldy	#commandLine
lb4b	lda	applicationID	set A to the caller's user ID
lb5	rtl		call the module (addr on stack)
ReturnFromProgram entry
quitReturn entry	quit call interception
	rep	#$FF	use default P reg
	lda	>myStack	restore our stack
	tcs
	plb		restore our data bank
	pld		restore our DP
	php		restore old prodos vector
	sei
	move4 oldE100A8,$E100A8
	move4 oldE100B0,$E100B0
	plp
	lda	exeFileType	if this is an NDA then
	cmp	#NDA
	bne	na1
	move4 tgrPtr,grPtr	  restore the main graphics window
	jsl	DisposeWindowList	  dump the NDA's windows
na1	pha		shut down the program
lb5a	ph2	applicationID
	ph2	restartable
	_UserShutDown
	pla
	ldx	restartable	if the program is restartable then
	beq	lb6
	ldx	#1	  set it's purge level to 1
	phx
	pha
	_SetPurgeAll
lb6	CloseGS clRec	close the program's files
	dec	lvLevel	reset the level
	SetLevelGS lvRec
lb7	return
;
;  Parameter based Quit call interception
;
quitTest anop		checks for ProDOS quit call
	php
	long	I,M
	pha
	phy
	phd
	tsc
	tcd
	ldy	#1
	lda	[8],Y
	cmp	#$0029
	jeq	quitReturn
	cmp	#$2029
	jeq	quitReturn
	pld
	ply
	pla
	plp		(fall into old prodos vector)

oldE100A8 ds	4	old $E100A8 jump vector
jml	jml	quitTest	jump for patching ProDOS vector
;
;  Stack based Quit call interception
;
quitTestB0 anop	checks for ProDOS quit call
	php
	long	I,M
	pha
	lda	7,S
	cmp	#$0029
	jeq	quitReturn
	cmp	#$2029
	jeq	quitReturn
	pla
	plp		(fall into old prodos vector)

oldE100B0 ds	4	old $E100A8 jump vector
jmlB0	jml	quitTestB0	jump for patching ProDOS vector
;
;  Local variables
;
myStack	ds	2	our stack pointer
regD	ds	2	our D register

applicationID ds 2	user ID

spDCB	dc	i'2'	set prefix DCB
	dc	i'9'
spName	ds	4

giDCB	dc	i'3'	get file info DCB
giName	ds	4
	ds	2
giFileType ds	2

lvRec	dc	i'1'	GetLevel/SetLevel call
lvLevel	ds	2

clRec	dc	i'1,0'	CloseGS record for close all

loadStack ds	2	S before loader call
	end

****************************************************************
*
*  MarkLine - Mark a line
*
*  Inputs:
*	lNum - line number to mark
*	ch - character to place in the mark column
*
****************************************************************
*
MarkLine start
	using BufferCommon

handle	equ	4	source file handle
sptr	equ	0	source file pointer

lcursor	equ	8	local copy of cursor
lcursorColumn equ 12	local copy of cursorColumn
lcursorRow equ 14	local copy of cursorRow
lwidth	equ	18	local copy of width
lheight	equ	20	local copy of height
lmaxHeight equ 22	local copy of maxHeight
lnumLines equ	24	local copy of numLines
ltopLine equ	28	local copy of topLine

lpageStart equ 32	local copy of pageStart

	subroutine (2:lNum,2:ch),36

	lda	sourcePtr	quit if there is no source file
	ora	sourcePtr+2
	jeq	lb9
	lda	lNum	convert lNum to a line displacement
	beq	ln1	 (disp from 0) rather than a line
	dec	lNum	 number (counting from 1)
ln1	move4 sourcePtr,sptr	place the source pointer in a usable place
	ldy	#expanded	if the file is not compacted or
	lda	[sptr],Y
	bne	su1
	ldy	#buffHandle	  the file has been moved then begin
	lda	[sptr],Y
	sta	handle
	iny
	iny
	lda	[sptr],Y
	sta	handle+2
	ldy	#2
	lda	[handle],Y
	ldy	#buffStart+2
	cmp	[sptr],Y
	bne	su1
	lda	[handle]
	dey
	dey
	cmp	[sptr],Y
	beq	su2
su1	ldy	#wPtr+2	  FindActiveFile(sourcePtr^.wPtr);
	lda	[sptr],Y
	pha
	dey
	dey
	lda	[sptr],Y
	pha
	jsl	FindActiveFile
	jsl	Expand	  Expand; {fixes pointers}
	jsl	Compact	  Compact;
	ldy	#buffLength-1	  set currentFile info
	short M
su1a	lda	currentFile,Y
	sta	[sptr],Y
	dey
	bpl	su1a
	long	M
	ph4	currentFile+buffHandle	  HLock(buffHandle);
	_HLock
su2	anop		  end; {if}
	ph2	disableScreenUpdates	save the screen update flag
	stz	disableScreenUpdates	allow screen updates
	ph2	busy	we are busy...
	lda	#1
	sta	busy
	ldy	#wPtr+2	set the port
	lda	[sptr],Y
	pha
	dey
	dey
	lda	[sptr],Y
	pha
	_StartDrawing

	ldy	#pageStart	move needed variables to
	lda	[sptr],Y	 local work space
	sta	lpageStart
	iny
	iny
	lda	[sptr],Y
	sta	lpageStart+2
	ldy	#cursor
	ldx	#0
lb0	lda	[sptr],Y
	sta	lcursor,X
	iny
	iny
	inx
	inx
	cpy	#leftColumn
	bne	lb0

	lda	lNum	if topLine > lNum then
	cmp	ltopLine
	bge	lb1
	ldy	#buffStart	  move to the start of the file
	lda	[sptr],Y
	sta	lpageStart
	sta	lcursor
	iny
	iny
	lda	[sptr],Y
	sta	lpageStart+2
	sta	lcursor+2
	stz	lcursorRow
	stz	lcursorRow+2
	stz	ltopLine
	stz	ltopLine+2
	lda	lNum	  move down lNum lines
	jsr	MoveDown
lb1	sub2	lNum,ltopLine	convert lNum to a screen row number
	lda	lNum	if lNum >= height then
	sec
	sbc	lheight
	inc	a
	bmi	lb2
	jsr	MoveDown	  move down lNum-height+1 lines
	lda	lheight	  lnum := height-1
	dec	a
	sta	lNum
lb2	lda	lNum	if cursorRow > lNum then
	cmp	lcursorRow
	bge	lb3
	move4 lpageStart,lcursor	  back up to the top of the page
	stz	lcursorRow
	stz	lcursorRow+2
lb3	lda	lcursorRow+2	while cursorRow < lNum do
	bmi	lb4
	lda	lcursorRow
	cmp	lNum
	bge	lb6
lb4	lda	[lcursor]	  skip to the next RETURN
	inc4	lcursor
	and	#$00FF
	cmp	#RETURN
	bne	lb4
	inc4	lcursorRow	  update cursorRow
	bra	lb3

lb6	lda	ch	if mark is a blank then
	cmp	#' '
	bne	lb7
	lda	[lcursor]	  if the first char is special then
	and	#$00FF
	cmp	#stepChar
	beq	lb6a
	cmp	breakChar
	beq	lb6a
	cmp	skipChar
	bne	lb7
lb6a	sta	ch	    use it
lb7	ph2	ch	DrawMark(ch,cursorRow,dispFromTop);
	ph2	lcursorRow
	ldy	#dispFromTop
	lda	[sptr],Y
	pha
	jsl	DrawMark

	ldy	#pageStart	move variables to global area
	lda	lpageStart
	sta	[sptr],Y
	iny
	iny
	lda	lpageStart+2
	sta	[sptr],Y
	ldy	#cursor
	ldx	#0
lb8	lda	lcursor,X
	sta	[sptr],Y 
	iny
	iny
	inx
	inx
	cpy	#leftColumn
	bne	lb8
	lda	sourcePtr	if this file is current then
	cmp	currentPtr
	bne	lb8b
	lda	sourcePtr+2
	cmp	currentPtr+2
	bne	lb8b
	ldy	#buffLength-1	  set currentFile info
	short M
lb8a	lda	[sptr],Y
	sta	currentFile,Y
	dey
	bpl	lb8a
	long	M

lb8b	ph4	grPtr	draw to the graphics window
	_StartDrawing
	pl2	busy	restore the busy flag
	pl2	disableScreenUpdates	restore the screen update flag
lb9	return
;
;  MoveDown - Scroll down in the file & repaint the screen
;
MoveDown anop
	tax
	beq	md2
md1	lda	[lpageStart]	skip a line
	inc4	lpageStart
	and	#$00FF
	cmp	#RETURN
	bne	md1
	inc4	ltopLine	update line dependent variables
	dec4	lcursorRow
	dex		next line...
	bne	md1
md2	ph2	lwidth	repaint the page
	ph2	lheight
	ldy	#dispFromTop
	lda	[sptr],Y
	pha
	ldy	#leftColumn
	lda	[sptr],Y
	pha
	ph4	lpageStart
	ldy	#gapStart+2
	lda	[sptr],Y
	pha
	dey
	dey
	lda	[sptr],Y
	pha
	ldy	#wPtr+2
	lda	[sptr],Y
	pha
	dey
	dey
	lda	[sptr],Y
	pha
	ph4	#currentFile+ruler
	jsl	DrawOneScreen
	ph2	ltopLine
	ldy	#vScroll+2
	lda	[sptr],Y
	pha
	dey
	dey
	lda	[sptr],Y
	pha
	_SetCtlValue
	rts
	end

****************************************************************
*
*  NDAAction - Action routine for NDAs running under the debugger
*
*  Inputs:
*	addr - address of the NDA
*
****************************************************************
*
NDAAction private
wmWhat	equ	0	taskRec for taskmaster call
wmMessage equ	2
wmWhen	equ	6
wmWhere	equ	10
wmModifiers equ 14
wmTaskData equ 16
wmTaskMask equ 20

lastTick equ	24	last tick count a call was made
tickCount equ	28	tick count
elapsed	equ	32	work area; elapsed ticks since last call

	subroutine (4:addr),36

	stz	lastTick	set the last tick count to 0
	stz	lastTick+2
	lda	#$2546	set the task mask for the taskMaster
	sta	wmTaskMask	 call
	stz	wmTaskMask+2
	ldy	#8	get the address of the action routine
	lda	[addr],Y
	sta	jml+1
	iny
	lda	[addr],Y
	sta	jml+2
lb1	lda	#3	call the action routine with a
	jsl	jml	 cursorAction code
	pha		get the current tick count
	pha
	_TickCount
	pl4	tickCount
	sub4	tickCount,lastTick,elapsed
	ldy	#16	get the NDA's period
	lda	[addr],Y
	beq	lb2	if the period is 0, execute it now
	inc	a	if the period is $FFFF, go check for an
	beq	lb3	 event
	dec	a
	ldx	elapsed+2	if the time has expired, go do a call
	bne	lb2
	cmp	elapsed
	bcs	lb3
lb2	move4 tickCount,lastTick	record the tick count
	lda	#2	do a runAction call
	jsl	jml
lb3	pha		get the next event
	ldy	#18
	lda	[addr],Y
	and	#$16E
	ora	#$142
	pha
	ph2	#0
	tdc
	pha
	_TaskMaster
	pla		quit if in go away region
	cmp	#22
	beq	lb5
	lda	wmWhat	if the event is a mouse down then
	cmp	#1
	bne	lb4
	ldy	#18	  if he doesn't want to see them then
	lda	[addr],Y
	and	#2
	jeq	lb1	    loop
lb4	tdc		do an eventAction call
	tax
	ldy	#0
	lda	#1
	jsl	jml
	brl	lb1
lb5	return 	return

jml	jml	jml
	end

****************************************************************
*
*  RemoveIntercepts - remove tool box intercepts
*
****************************************************************
*
RemoveIntercepts private
	using InterceptCommon
menuHandle equ 0	handle of application menu bar
menuPtr	equ	4	pointer to application menu bar

	subroutine ,8

	php		reset system tool vector
	sei
	move4 toolVector,$E10000
	plp
	lda	menuChanged	if the menu bar has changed then
	jeq	lb4
	lda	ourMenu	  make the application menu current
	beq	lb1
	jsr	Switch
lb1	pha		  get the application's menu bar
	pha
	_GetMenuBar
	pl4	menuHandle	  get the addr of the first menu handle
	ldy	#2
	clc
	lda	[menuHandle]
	adc	#$24
	sta	menuPtr
	lda	[menuHandle],Y
	adc	#0
	sta	menuPtr+2
lb2	ldy	#2	  while there is a non-nil handle do
	lda	[menuPtr],Y
	tax
	dey
	dey
	ora	[menuPtr],Y
	beq	lb3
	phx		    dispose of the menu
	lda	[menuPtr],Y
	pha
	_DisposeMenu
	add4	menuPtr,#4	    next menu handle
	bra	lb2
lb3	ph4	menuHandle	  dispose of the menu bar
	_DisposeHandle
	ph4	sysMenuBar	  restore ours
	_SetSysBar
	ph4	#0
	_SetMenuBar
	pha
	_FixMenuBar
	pla
	_HideCursor
	_DrawMenuBar
	_ShowCursor
lb4	return
	end

****************************************************************
*
*  RestorePrefix9 - set prefix 9 to its startup value
*
****************************************************************
*
RestorePrefix9 private
	using	CommonCOut

	inc	p9DCB+4
	inc	p9DCB+4
	SetPrefixGS p9DCB
	dec	p9DCB+4
	dec	p9DCB+4
	rtl
	end

****************************************************************
*
*  Sleep - write the "wake up" file to disk
*
*  Inputs:
*	name - address of the name of the config file
*
****************************************************************
*
Sleep	private
	using BufferCommon
	using CommonCOut
handle	equ	0	file handle
ptr	equ	4	file pointer
wp	equ	8	window pointer
p1	equ	12	pointer into wptrs array
p2	equ	16	work pointer
loop	equ	20	loop counter

	subroutine (4:name),22
;
;  Get space for the file
;
	pha		get a block of memory for the file
	pha
	ph4	#7000
	ph2	~user_ID
	ph2	#$8000
	ph4	#0
	_NewHandle
	pl4	0
	bcc	lb1
	jsl	OutOfMemory
	brl	rts
lb1	ldy	#2	dereference the handle
	lda	[handle]
	sta	ptr
	lda	[handle],Y
	sta	ptr+2
;
;  Save the scalars
;
	lda	autoSave
	sta	[ptr]
	ldy	#2
	lda	compileList
	sta	[ptr],Y
	iny
	iny
	lda	compileSymbol
	sta	[ptr],Y
	iny
	iny
	lda	compileDebug
	sta	[ptr],Y
	iny
	iny
	lda	compileLink
	sta	[ptr],Y
	iny
	iny
	lda	linkList
	sta	[ptr],Y
	iny
	iny
	lda	linkSymbol
	sta	[ptr],Y
	iny
	iny
	lda	linkSave
	sta	[ptr],Y
	iny
	iny
	lda	linkExecute
	sta	[ptr],Y
	iny
	iny
	lda	fileKind
	sta	[ptr],Y
	iny
	iny
	lda	profile
	sta	[ptr],Y
;
;  Get the prefix values
;
	ldy	#22	set the buffer sizes
	lda	#260
	sta	[ptr],Y
	ldy	#22+260
	sta	[ptr],Y
	ldy	#22+260+260
	sta	[ptr],Y
	add4	ptr,#22,prefix	prefix 8
	lda	#8
	sta	prefixNum
	GetPrefixGS prDCB
	add4	prefix,#260	prefix 13
	lda	#13
	sta	prefixNum
	GetPrefixGS prDCB
	add4	prefix,#260	prefix 16
	lda	#16
	sta	prefixNum
	GetPrefixGS prDCB
;
;  Record the status of the system windows
;
	pha		save the front window
	pha
	_FrontWindow
	lda	#wptrs	set up the p1 array index
	sta	p1
	add4	ptr,#802	set the file pointer to the correct spot
rs1	ldy	#2	fetch the window handle
	lda	(p1)
	sta	p2
	ora	(p1),Y
	beq	rs4	branch if we're at the end of the array
	lda	(p1),Y
	sta	p2+2
	lda	[p2]	get the window pointer
	sta	wp
	lda	[p2],Y
	sta	wp+2
	ora	wp	set the open flag
	beq	rs2
	lda	#1
rs2	sta	[ptr]
	beq	rs3	branch if the window is closed
	ph4	wp	select the window
	_StartDrawing
	jsr	SaveInfo	save the window info
rs3	add4	ptr,#10	update the file pointer
	add2	p1,#4	update the wptrs array index
	bra	rs1	next window

rs4	lda	graphicsWindowOpen	if not graphicsWindowOpen then
	bne	uw1
	sub4	ptr,#20,p1	   mark the graphics window as closed
	lda	#0
	sta	[p1]
;
;  Save any user windows
;
uw1	move4 filePtr,p1	get the pointer to the first record
	lda	#20	allow a max of 20 user windows
	sta	loop
uw2	lda	p1	branch if there are no more windows
	ora	p1+2
	beq	uw5
	ldy	#isFile	branch if the file does not exist on
	lda	[p1],Y	 disk
	beq	uw4
	lda	#1	set the active window flag
	sta	[ptr]
	ldy	#wPtr+2	select the window
	lda	[p1],Y
	pha
	dey
	dey
	lda	[p1],Y
	pha
	_StartDrawing
	jsr	SaveInfo	save the window info
	ldy	#language	save the language
	lda	[p1],Y
	ldy	#10
	sta	[ptr],Y
	add4	ptr,#12	save the file name
	add4	p1,#pathName,wp
	ldy	#256
uw3	lda	[wp],Y
	sta	[ptr],Y
	dey
	dey
	bpl	uw3
	add4	ptr,#258	update the file pointer
uw4	ldy	#next	get the next record ptr
	lda	[p1],Y
	tax
	iny
	iny
	lda	[p1],Y
	sta	p1+2
	stx	p1
	dec	loop	next window
	bne	uw2
uw5	lda	#0	zero the next file entry
	sta	[ptr]
	add4	ptr,#2	update the file ptr

	_StartDrawing	select the original window
;
;  Save the file
;
	lda	#3	save the file
	sta	ffAction
	move4 handle,ffFileHandle
	sec
	lda	ptr
	sbc	[handle]
	sta	ffFileLength
	move4 name,ffPathName
	FastFileGS ffDCB
	tax
	beq	sf1
	lda	#9
	pha
	phx
	jsl	FlagError
sf1	lda	#7	purge the file
	sta	ffAction
	move4 name,ffPathName
	FastFileGS ffDCB
rts	return
;
;  SaveInfo - save the info about the current window
;
SaveInfo ph4	#rect	get the size and location of the window
	_GetPortRect
	ph4	#rect
	_LocalToGlobal
	ldy	#2	save the info
	lda	rect+2
	sta	[ptr],Y
	iny
	iny
	lda	rect
	sta	[ptr],Y
	iny
	iny
	lda	rect+6
	sta	[ptr],Y
	iny
	iny
	lda	rect+4
	sta	[ptr],Y
	rts
;
;  Local data areas
;
rect	ds	8

prDCB	dc	i'2'	get prefix DCB
prefixNum ds	2
prefix	ds	4

ffDCB	dc	i'14'	fast file DCB
ffAction ds	2	action code
ffIndex	ds	2	index number
ffFlags	dc	i'$C000'	status flags
ffFileHandle ds 4	handle of the file
ffPathName ds	4	pointer to the path name
ffAccess dc	i'$C3'	ProDOS access code
ffFileType dc	i'6'	file type
ffAuxType ds	4	aux file type
ffStorageType dc i'1'	storage type
ffCreate ds	8	create date/time
ffMod	ds	8	mod date/time
ffOption	dc	a4'0'	option list
ffFileLength ds 4	length of the file in bytes
ffBlocksUsed ds 4	# blocks in the file
	end

****************************************************************
*
*  SpecialChar - handle special editing characters for ConsoleKeyIn
*
*  Inputs:
*	A - potential special character
*	X - modifier keys
*
*  Outputs:
*	C - set if the character was an editing character
*
****************************************************************
*
SpecialChar start
	using CommonCOut
	using BufferCommon
delete	equ	$7F	DELETE key code
return	equ	13	RETURN key code
   
	and	#$007F	reject all control keys
	beq	lb1
	cmp	#' '
	bge	lb1
	cmp	#return
	bne	reject
lb1	tay		reject all open-apple (editing) keys
	txa
	and	#$0100
	bne	reject
	cpy	#delete	if key = delete then
	bne	lb2
	jsl	UpdateScreen2	  take care of old actions
	ph4	shellWindow	  get the correct window
	jsl	FindActiveFile
	ph4	currentFile+wPtr
	_StartDrawing
	jsl	FollowCursor	  find the cursor
	ph2	currentFile+insert	  get the screen ready
	ph2	disableScreenUpdates
	stz	currentFile+insert
	stz	disableScreenUpdates
	ph2	#1	  back up
	jsl	MoveLeft
	jsl	DoDeleteToEOL	  delete to eol
	pl2	disableScreenUpdates	  restore the old settings
	pl2	currentFile+insert
	lda	#1	  mark for a subsequent space
	sta	lastWasDelete
lb2	anop		endif
	clc
	rts

reject	sec
	rts
	end

****************************************************************
*
*  StartConsole - start the console driver
*
****************************************************************
*
StartConsole private
	using CommonCOut
ptr	equ	0	work pointer

	subroutine ,4
	phb
	phk
	plb

	GetDevNumberGS dnRec	get the console device number
	lda	dnDevnum
	sta	stDevnum
	DStatusGS stRec	get the character status
	move4	COut,ptr	save the COut vector
	ldy	#2
	lda	[ptr]
	sta	OldCOut
	lda	[ptr],Y
	sta	OldCOut+2
	lda	JmpCOut	set up our console out
	sta	[ptr]
	lda	JmpCOut+2
	sta	[ptr],Y
	ldy	#4	insert our 5 byte patch, saving the
	lda	[ptr],Y	  originals
	sta	oldBytes
	lda	patch
	sta	[ptr],Y
	iny
	iny
	lda	[ptr],Y
	sta	oldBytes+2
	lda	patch+2
	sta	[ptr],Y
	iny
	lda	[ptr],Y
	sta	oldBytes+3
	lda	patch+3
	sta	[ptr],Y
         ldy	#$61	swap our patch address for the
	lda	[ptr],Y	  ConsoleOut jsr address
	sta	oldWWChar
	clc
	lda	#4
	adc	ptr
	sta	[ptr],Y

	lda	KeyIn	save the KeyIn Vector
	sta	ptr
	lda	KeyIn+2
	sta	ptr+2
	lda	[ptr]
	sta	OldKeyIn
	ldy	#2
	lda	[ptr],Y
	sta	OldKeyIn+2
	lda	JmpKeyIn	set up our console input
	sta	[ptr]
	lda	JmpKeyIn+2
	sta	[ptr],Y
	ldx	#0	swap in our KeyIn patch code
	ldy	#$B79
	short	M
lb1	lda	[ptr],Y
	sta	OldPatch2,X
	lda	patch2,X
	sta	[ptr],Y
	iny
	inx
	cpx	#patch2Len
	bne	lb1
	long	M

	stz	chBuffLen	no characters written
	ph4	#InactiveCheck	install check for inactivity
	_SetHeartBeat
	lda	#1	disable normal screen updates
	sta	disableScreenUpdates
	ph4	grPtr	graphics window is the default
	_StartDrawing

	plb
	return

JmpCOut	jml	ConsoleCOut
JmpKeyIn	jml	ConsoleKeyIn

patch	jsl	ConsoleCOut	console output patch
	rts

patch2	php		console input patch
	long	I,M
	jsl	ConsoleKeyAvail
	bcc	pa1
	jsl	ConsoleKeyIn
	pha
	xba
	and	#$00FF
	tax
	pla
	and	#$00FF
	plp
	sec
	rts
pa1	clc
	plp
	rts
	end

****************************************************************
*
*  StopConsole - stop the console driver
*
****************************************************************
*
StopConsole private
	using BufferCommon
	using CommonCOut
ptr	equ	0	work pointer

	subroutine ,4
;
;  Purge the text buffers
;
	ph4	#InactiveCheck	remove heartbeat checks
	_DelHeartBeat
	stz	busy	not busy, now
	jsl	UpdateScreen	check for recent changes
	stz	disableScreenUpdates	enable normal screen updates
	ph4	currentFile+wPtr	erase the cursor, if any
	_StartDrawing
	jsl	FollowCursor
	ph2	currentFile+cursorRow
	jsl	DrawLine
;
;  Restore default console output
;
	GetDevNumberGS dnRec	get the console device number
	lda	dnDevnum
	sta	stDevnum
	DStatusGS stRec	get the character status
	move4	COut,ptr	restore the COut vector
	ldy	#2
	lda	OldCOut
	sta	[ptr],Y
	lda	OldCOut+2
	sta	[ptr],Y
	ldy	#4	remove our 5 byte COut patch
	lda	oldBytes
	sta	[ptr],Y
	iny
	iny
	lda	oldBytes+2
	sta	[ptr],Y
	iny
	lda	oldBytes+3
	sta	[ptr],Y
         ldy	#$61	restore the original jsr Cout
	lda	oldWWChar
	sta	[ptr],Y

	lda	KeyIn	restore the KeyIn Vector
	sta	ptr
	lda	KeyIn+2
	sta	ptr+2
	lda	OldKeyIn
	sta	[ptr]
	ldy	#2
	lda	OldKeyIn+2
	sta	[ptr],Y
	ldx	#0	swap in our KeyIn patch code
	ldy	#$B79
	short	M
kp1	lda	oldPatch2,X
	sta	[ptr],Y
	iny
	inx
	cpx	#patch2Len
	bne	kp1
	long	M
;
;  Switch to source window for active I/O
;
	lda	sourcePtr	back to source window
	ora	sourcePtr+2
	beq	lb1
	ph4	sourcePtr
	jsl	FindActiveFile
	tax
	beq	lb2
lb1	ph4	currentFile+wPtr
	_StartDrawing
lb2	return
	end

****************************************************************
*
*  Switch - switch menu bars
*
*  Inputs:
*	ourMenu - is the current menu bar ours?
*	appMenuBar - handle of application menu
*	sysMenuBar - our menu bar
*
****************************************************************
*
Switch	private
	using InterceptCommon

	lda	ourMenu	fetch the current menu and
	bne	lb1	  push the new menu handle
	pha
	pha
	_GetMenuBar
	pl4	appMenuBar
	ph4	sysMenuBar
	bra	lb2
lb1	ph4	appMenuBar
lb2	_SetSysBar	draw the new bar
	ph4	#0
	_SetMenuBar
	pha
	_FixMenuBar
	pla
	_HideCursor
	_DrawMenuBar
	_ShowCursor
	lda	ourMenu	ourMenu := not ourMenu
	eor	#1
	sta	ourMenu
	pha		flush the event queue
	ph2	#$0F6E
	ph2	#0
	_FlushEvents
	pla
	rts
	end

****************************************************************
*
*  TestMouse - test for mouse down in switch or step
*
*  If a mouse down occurs in the switch region, the menu bar
*  is switched, and the routine returns with A=0.  If there is
*  a mouse down in the step, returns with A=1, else returns
*  with A=0.
*
****************************************************************
*
TestMouse private
	using InterceptCommon

	lda	menuChanged	return if the menu bar has never been
	beq	no	 changed
	jsr	MousePos	return if the mouse is not
	bcc	no	 down in one of our areas
	lda	mouseArea
	beq	no
	sta	lastArea	invert the area of interest
	jsr	Invert
lb1	jsr	MousePos	repeat until the mouse is let up...
	bcc	lb2
	lda	mouseArea	  loop if we are still in the inverted
	cmp	lastArea	   area
	beq	lb1
	lda	lastArea	  un-invert the inverted area
	jsr	Invert
	lda	mouseArea	  invert the new area, saving its #
	sta	lastArea
	jsr	Invert
	bra	lb1	  loop
lb2	lda	lastArea	un-invert the area
	jsr	Invert
	ldx	mouseArea	if not in one of our boxes, quit
	beq	no
	dex		if in the foot, return with carry set
	bne	lb3
	lda	#1
	rtl
lb3	jsr	Switch	switch menu bars
no	lda	#0
	rtl
;
;  Find the area where the mouse is, and see if the button is down.
;
MousePos pha		get the mouse position
	pha
	pha
	_ReadMouse
	pla
	ply
	plx
	stz	mouseArea	set the area to:
	cpy	#13
	bge	mp1	   0 -> not in one of our icons
	cpx	#576	   1 -> foot icon
	blt	mp1	   2 -> switch icon
	inc	mouseArea
	cpx	#608
	blt	mp1
	inc	mouseArea
mp1	asl	a	if mouse down, set carry, else clear it
	rts
;
;  Invert the numbered area
;
Invert	pha		hide the cursor
	_HideCursor
	pla
	dec	a	return if area is not an icon
	bmi	in4
	beq	in1	set the initial index
	ldx	#160+152
	bra	in2
in1	ldx	#160+144
in2	ldy	#11	invert the icon
in3	lda	$E12000,X
	eor	#$FFFF
	sta	$E12000,X
	lda	$E12002,X
	eor	#$FFFF
	sta	$E12002,X
	lda	$E12004,X
	eor	#$FFFF
	sta	$E12004,X
	lda	$E12006,X
	eor	#$FFFF
	sta	$E12006,X
	txa
	clc
	adc	#160
	tax
	dey
	bne	in3
in4	_ShowCursor	bring back the cursor
	rts

lastArea ds	2
mouseArea ds	2
	end
