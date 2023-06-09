	mcopy prism.macros
****************************************************************
*
*  InstallIntercepts - install shell intercepts
*  RemoveIntercepts - remove shell intercepts
*
****************************************************************
*
InstallIntercepts private

	ChangeVector cv0
	ChangeVector cv1
	ChangeVector cv2
	rtl

cv0	dc	i'0,0'
	dc	a4'EditIntercept'
cv0o	ds	4

cv1	dc	i'0,1'
	dc	a4'cns'
cv1o	ds	4

cv2	dc	i'0,2'
	dc	a4'Abort'
cv2o	ds	4

RemoveIntercepts entry
	move4 cv0o,cw0o
	move4 cv1o,cw1o
	move4 cv2o,cw2o
	ChangeVector cw0
	ChangeVector cw1
	ChangeVector cw2
	rtl

cw0	dc	i'0,0'
cw0o	ds	8

cw1	dc	i'0,1'
cw1o	ds	8

cw2	dc	i'0,2'
cw2o	ds	8
;
;  Cns - ignore console characters
;
Cns	php
	long	I,M
	plx
	ply
	pla
	phy
	phx
	plp
	rtl
	end

****************************************************************
*
*  SystemError - Handle run time errors
*
*  Inputs:
*	4,S - error number
*
****************************************************************
*
SystemError start
	longa on
	longi on
errorNumber equ 4	error number

	lda	errorNumber,S
	pha
	ph4	#msg
	_SysFailMgr

msg	dw	'System error: '
	end

****************************************************************
*
*  DPArea - our DP/stack segment area
*
****************************************************************
*
DPArea	start DPSegment
	kind	$12

	ds	17*256
	end

****************************************************************
*
*  ~_BWCommon - Global data for the compiler
*
****************************************************************
*
~_BWCommon start
;
;  Misc. variables
;
~CommandLine entry	address of the shell command line
	ds	4
~EOFInput entry 	end of file flag for input
	ds	2
~EOLNInput entry	end of line flag for input
	ds	2
ErrorOutput entry	error output file variable
	dc	a4'~ErrorOutputChar'
~ErrorOutputChar entry	error output file buffer
	ds	2
Input	entry		standard input file variable
	dc	a4'~InputChar'
~InputChar entry	standard input file buffer
	ds	2
~MinStack entry 	lowest reserved bank zero address
	ds	2
Output	entry		standard output file variable
	dc	a4'~OutputChar'
~OutputChar entry	standard output file buffer
	ds	2
~RealVal entry		last real value returned by a function
	ds	10
~SANEStarted entry	did we start SANE?
	dc	i'0'
~ThisFile entry 	pointer to current file variable
	ds	4
~ToolError entry	last error in a tool call (Pascal)
	ds	2
~User_ID entry		user ID (Pascal, libraries)
	ds	2
ioFlag	entry		input output flag
	ds	2
~StringList entry	string buffer list
	ds	4
;
;  Traceback variables
;
~ProcList entry 	traceback list head
	ds	4
~LineNumber entry	current line number
	ds	2
~ProcName entry 	current procedure name
	ds	32
;
;  Universal quit code
;
~Quit	entry
	jsl	ShutDown
	quit	qt_dcb	return to the calling shell

qt_dcb	anop		quit DCB
	dc	a4'qt_flags'
qt_flags dc	i'0'
;
;  ShutDown - common shutdown code for RTL and QUIT exits
;
~ShutDown entry
ShutDown pha		save the return code
	lda	>~SANEStarted	if we started SANE then
	beq	qt1
	_SANEShutDown	  shut it down
	stz	~SANEStarted	  clear the flag (for restarts)
qt1	jsl	~MM_Init	zero the memory manager
	ph2	>~User_ID	dispose of any remaining memory
	_DisposeAll	 allocated by the memory manager
	pla		restore the return code
	rts
	end

****************************************************************
*
*  ~_BWStartUp - Compiler initialization
*
*  Inputs:
*	A - user ID
*	X-Y - address of the command line
*	D - lowest reserved bank zero address
*	4,S - amount of stack space to reserve
*
*  Outputs:
*	~User_ID - user ID
*	~CommandLine - address of the command line
*	~MinStack - lowest reserved bank zero address
*	~InputChar - set to ' '
*
****************************************************************
*
~_BWStartUp start
;
;  Set up initial registers
;
	phk		set the data bank register
	plb
	ora	#$0100	use local user ID
	sta	~User_ID	save the user ID for memory manager use
	case	on
	lda	ownerid
	beq	lb1
	dc	i1'$8F'	(sta long)
ownerid	dc	s3'_ownerid'
lb1	anop
	case	off
	stx	~CommandLine+2	save the address of the command line
	sty	~CommandLine
;
;  Set stack values, initialize SANE and traceback code
;
	lda	#DPArea	set up minStack
	sta	~MinStack
	pha		if SANE has not been started then
	_SANEStatus
	pla
	bne	sn1
	lda	~MinStack	  get some bank zero memory for SANE
	pha
	clc
	adc	#$0100
	sta	~MinStack
	_SANEStartUp	  initialize SANE
	lda	#1	  set the SANE startup flag
	sta	~SANEStarted
sn1	lda	#' '	reset(input)
	sta	~InputChar
	stz	~EOLNInput
	stz	~EOFInput
	stz	~LineNumber	initialize traceback info
	stz	~ProcName
	stz	~ProcList
	stz	~ProcList+2
	stz	~StringList	initialize the string buffer list
	stz	~StringList+2
	stz	~thisFile	initialize file lists
	stz	~thisFile+2
	rtl
	end

****************************************************************
*
*  ~Halt - Stop execution and return with error code
*
*  Inputs:
*	error - error code
*
****************************************************************
*
~Halt	start
	using ~_IOCommon
error	equ	4

	lda	error,S
	brl	~Quit
	end
