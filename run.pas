{$optimize 7}
{---------------------------------------------------------------}
{								}
{  Run								}
{								}
{  The Run module implements the commands in the Run menu, as	}
{  well as the routines needed to handle the enter key,		}
{  console I/O, and the standard graphics window.		}
{								}
{  By Mike Westerfield						}
{								}
{  Copyright 1987						}
{  Byte Works, Inc.						}
{								}
{---------------------------------------------------------------}

unit Run;

interface

{$segment 'Buffer'}

uses Common, QuickDrawII, EventMgr, WindowMgr, MemoryMgr, ControlMgr, MenuMgr,
  MscToolSet, ScrapMgr, LineEdit, DialogMgr, GSOS, ORCAShell, SFToolSet;

{$LibPrefix '0/obj/'}

uses PCommon, Buffer;

type
   compileKind = (memory,disk,scan);	{kinds of compiles}

var
   memAddr: longint;			{address of 1st byte in memory window}
   regS: integer;			{program's SP}
   returnCount: integer; 		{return counter}
   stepThru: boolean;			{step through subroutines?}
   stepOnReturn: boolean;		{start stepping on next return?}
 
   lsFile,ldFile: gsosOutString;	{work buffers get/set LInfo calls}
   lnamesList,liString: gsosOutString;

					{special window pointers & controls}
					{----------------------------------}
   vrGrow,vrVScroll: ctlRecHndl;	{variables window controls}
   vrPtr: grafPortPtr;			{variables window}

   shellPtr: buffPtr;			{pointer to shell file}
   shellWindow: grafPortPtr;		{pointer to shell window}

   graphicsWindowOpen: boolean;		{is the graphics window visible?}
   grGrow: ctlRecHndl;			{grow control for graphics window}
   grPtr: grafPortPtr;			{graphics window pointer}


procedure CloseGraphics;

{ close the graphics window					}


procedure DoCompile (kind: compileKind; flags: integer; menuNum: integer);

{ do a compile/link/execute sequence				}
{								}
{ Parameters:							}
{    kind - kind of compile					}
{    flags -							}
{    menuNum -							}


procedure DoCompile2;

{ get compile options						}


procedure DoExecute;

{ execute a program						}


procedure DoExecuteOptions;

{ execute a program						}


procedure DoGraphics;

{ Show or hide the graphics window				}
          

procedure DoLink;

{ get link options						}


procedure DoVariables; extern;

{ open or bring the variables window to front			}


procedure DoVariablesMouseDown (h,v: integer);

{ handle a mouse down event in the variables window		}
{								}
{ Parameters:							}
{    h,v - position in local coordinates 			}


procedure DoVariablesScroll (part: integer);

{ handle a scroll bar event in the variables window		}
{								}
{ Parameters:							}
{    part - scroll bar part number				}


procedure ExecuteSelection; extern;

{ Execute the current selection or line				}


procedure GetShellWindow;

{ find and activate a shell window				}


procedure MarkLine (lNum, ch: integer); extern;

{ mark a line							}
{								}
{ Parameters:							}
{    lNum - line number to mark					}
{    ch - character to place in the mark column			}


procedure InitRun; extern;

{ variable initialization for the Run unit			}


procedure SetSourceWindow (sourceName: gsosInStringPtr);

{ Change the source window to the named window			}
{								}
{ Parameters:							}
{    sourceName - source window name				}


procedure UpdateGrWindow;

{ update the graphics window					}


procedure RedoVrWindow;

{ Redo the variables window                                     }

{------------------------------------------------------------------------------}

implementation

const
   vHeight	=	  9;		{height of a line in the var window}

type
					{Misc}
					{----}
   compKind = (thisWindow,diskFile);	{ways to compile a file}
 
					{variables display}
					{-----------------}
   bytePtr = ^byte;			{for assignment compatibility}
   entryArrayPtr = ^entryArray;
   entryArray = record			{entry in a variable symbol table}
      case boolean of
	 true : (startVal,endVal,size: longint); {array index info}
	 false: (name: pStringPtr;	{name of a variable}
		 value: bytePtr; 	{pointer to variable value}
		 longAddr: byte; 	{long addr or DP?}
		 format: byte;		{format of variable}
		 numSubscripts: integer; {# of subscripts or fields}
		 );
      end;
 
					{base variable formats}
   varFormats = (i1,i2,i4,r4,r8,r10,cStr,pStr,c1,b1,cp,p4,record1,derived,ptr4,bad);
 
   refPtr = ^refRecord;			{for dereferencing addresses}
   refRecord = record
      next: refPtr;
      offset: longint;
      end;

   varPtr = ^varRecord;			{variables window variable}
   varRecord = record
      last,next: varPtr; 		{doubly linked list}
      expr: pStringPtr;			{expression in ASCII form}
      vf: varFormats;			{type of variable}
      addr: bytePtr;			{pointer to variable value}
      ref: refPtr;			{dereference record (used when addr is a pointer)}
      end;

   procInfoPtr = ^procInfo;
   procInfo = record
      last,next: procInfoPtr;		{doubly linked list}
      name: pStringPtr;			{name of this proc}
      length: integer;			{length of the variable table}
      symbols: entryArrayPtr;		{pointer to symbol table}
      vars: varPtr;			{pointer to list of visible variables}
      DP: integer;			{DP address on entry; 0 -> globals}
      topVar,numVars: integer;		{top & # of variables in list}
      end;

   templatePtr = ^templateRecord;	{variable templates}
   templateRecord = record
      last,next: templatePtr;		{doubly linked list}
      name: pStringPtr;			{name of this proc}
      vars: varPtr;			{pointer to list of visible variables}
      topVar,numVars: integer;		{top & # of variables in list}
      end;
      
					{profiler}
					{--------}
   subNamePtr = ^subName;		{name of a subroutine}
   subName = string[10];
 
   profilePtr = ^profileRecord;
   profileRecord = record		{record for one subroutine}
      heartbeats: longint;		{# heartbeats while active}
      calls: longint;			{# calls}
      name: subName;			{actual name for report}
      namePtr: pStringPtr;		{ptr to name - for compares}
      next: profilePtr;			{link}
      end;
 
   subPtr = ^subRecord;
   subRecord = record			{subroutine call stack}
      ptr: profilePtr;
      next: subPtr;
      end;
 
   nameRecPtr = ^nameRec;		{file name stack}
   nameRec = record
      next: nameRecPtr;
      name: gsosInString;
      end;
 
					{window list management}
					{----------------------}
   windowRecordPtr = ^windowRecord;	{pointer type for window list}
   windowRecord = record
      next: windowRecordPtr;		{next item in list}
      owp: grafPortPtr;			{our window pointer}
      end; {record}

var
					{misc}
					{----}
   lineNumber: integer;			{line number of trace; 0 if none}

   linkRec: gsosInStringPtr;		{linker info}

   ourMenu: boolean;			{are we using our menu bar?}
 
   windowList: windowRecordPtr;		{list of our windows (during run only)}

					{profiler}
					{--------}
   profileLink: profilePtr;		{head of profile list}
   subLink: subPtr;			{head of subroutine chain}
 
   nameList: nameRecPtr; 		{file name stack}

					{variables display}
					{-----------------}
   currentProc: procInfoPtr;		{variable info about current proc}
   procList: procInfoPtr;		{head of variables list}
   templateList: templatePtr;		{list of symbol templates}

   vrHeaderChanged: boolean;		{has the header changed?}

					{compilation}
					{-----------}
   eFile: gsosOutString;		{executable file name}
   liDCB: getlInfoDCBGS;		{language info DCB}
   loadSucceeded: boolean;		{loader success; set by LoadAndCall}
   oldVector5: ptr;			{old cop vector}

					{execute options}
					{---------------}
   executeMode: statusType;		{step/trace/go mode}
   executeCommandLine: pString;		{command line}
   commandLine: packed array[1..266] of char; {command line}

					{linker AuxType options}
                                        {----------------------}
   gsosAware: boolean;			{is the application GS/OS aware?}
   messageAware: boolean;		{is the application message genter aware?}
   deskAware: boolean;			{is this a desktop application?}

{------------------------------------------------------------------------------}

procedure CheckMenuItems; extern;

{ check and uncheck file dependent menu items			}


procedure CopProcessor; extern;

{ process COP interupt						}


procedure Events (lastEvent: eventRecord; event: integer;
   var done: boolean; executing: boolean); extern;

{ handle the main event loop					}
{								}
{ Parameters:							}
{    lastEvent - last event record				}
{    event - event code						}
{    done - done flag						}
{    executing - 						}


procedure InstallIntercepts; extern;

{ install tool intercepts					}


procedure InstallProfiler; extern;

{ install the profiler's heartbeat interupt handler             }


procedure LoadAndCall (namePtr: gsosInStringPtr; restartable,traceAllowed: boolean);
   extern;

{ load and call a compiler, linker, etc. 			}
{								}
{ Parameters:							}
{    namePtr - full path name of the module			}
{    restartable - can the application be restarted?		}
{    traceAllowed - are we allowed to do a native code trace?	}


procedure RemoveIntercepts; extern;

{ remove tool intercepts 					}


procedure RemoveProfiler; extern;

{ remove the profiler's heartbeat interupt handler              }


procedure RestorePrefix9; extern;

{ Set prefix 9 to it's startup value				}


procedure Sleep (name: gsosInStringPtr); extern;

{ Write the "wake up" file to disk				}
{								}
{ parameters:							}
{    name - name of the wake up file				}


procedure StartConsole; extern;

{ start the console driver					}


procedure StopConsole; extern;

{ stop the console driver					}

{------------------------------------------------------------------------------}

{$DataBank+}

procedure VrInfo(r: rect; infoData: longint; wp: grafPortPtr);

{ draw the info bar for the variables window			}
{								}
{ Parameters:							}
{    r - info bar rectangle					}
{    infoData - user defined info bar data			}
{    wp - window containing the info bar 			}


   procedure SetDimmMask (dimmed: boolean);
 
   { set the mask to dimm?					}
   {								}
   { Parameters: 						}
   {	dimmed - dimmed? 					}
 
   var
      i: integer;			{loop variable}
      mymask: mask;			{pen mask}
 
   begin {SetDimmMask}
   if dimmed then begin
      mymask[0] := $55;
      mymask[1] := $CC;
      mymask[2] := $55;
      mymask[3] := $CC;
      mymask[4] := $55;
      mymask[5] := $CC;
      mymask[6] := $55;
      mymask[7] := $CC;
      end {if}
   else
      for i := 0 to 7 do
	 mymask[i] := $FF;
   SetPenMask(mymask);
   end; {SetDimmMask}


begin {VrInfo}
EraseRect(r);				{clear old info}
SetSolidPenPat(0);			{draw the down arrow}
SetPenMode(0);
SetPenSize(2,1);
SetDimmMask(true);
if currentProc <> nil then
   if currentProc^.last <> nil then
      SetDimmMask(false);
MoveTo(8,r.v1+8); LineTo(8,r.v1+1);
MoveTo(4,r.v1+5); LineTo(8,r.v1+7); LineTo(12,r.v1+5);
SetDimmMask(true);			{draw the up arrow}
if currentProc <> nil then
   if currentProc^.next <> nil then
      SetDimmMask(false);
MoveTo(23,r.v1+8); LineTo(23,r.v1+1);
MoveTo(19,r.v1+3); LineTo(23,r.v1+1); LineTo(27,r.v1+3);
SetDimmMask(true);			{draw the star}
if currentProc <> nil then
   SetDimmMask(false);
MoveTo(35, r.v1+8); LineTo(38, r.v1+1); LineTo(41, r.v1+8);
LineTo(34, r.v1+3); LineTo(42, r.v1+3); LineTo(35, r.v1+8);
SetDimmMask(false);			{draw the dividing lines}
MoveTo(45,r.v1); LineTo(45,r.v1+10);
MoveTo(30,r.v1); LineTo(30,r.v1+10);
MoveTo(15,r.v1); LineTo(15,r.v1+10);
SetPenSize(1,1); 			{restore pen to normal}
if currentProc <> nil then begin 	{draw the procedure name}
   SetForeColor(0);
   SetBackColor(15);
   MoveTo(49,r.v1+8);
   DrawStringWidth(dswCondense+dswTruncRight, currentProc^.name, r.h2-50);
   end; {if}
end; {VrInfo}

{$DataBank-}


procedure Hex (var str: pString; val: longint);

{ convert the lsb to a hex string, appending this to Hex 	}
{								}
{ Parameters:							}
{    str - string to stuff the hex value into			}
{    val - hex value						}

var
   byteval: integer;			{for more efficient conversions}

begin {Hex}
byteval := (long(val).lsw >> 4) & $F | ord('0');
if byteval > ord('9') then
   byteval := byteval+7;
str := concat(str,chr(byteval));
byteval := long(val).lsw & $F | ord('0');
if byteval > ord('9') then
   byteval := byteval+7;
str := concat(str,chr(byteval));
end; {Hex}


procedure DrawVariables (isUpdate: boolean);

{ redraw the variables window					}
{								}
{ parameters:							}
{    isUpdate: called from an update routine?			}

var
   r: rect;				 {port rectangle}

 
   procedure DrawContent;
 
   { draw the list of variables in the content area		}
 
   type
      bytePtr = ^byte;			{types of variables}
      integerPtr = ^integer;
      longintPtr = ^longint;
      realPtr = ^real;
      doublePtr = ^double;
      extendedPtr = ^extended;
      compPtr = ^comp;
      cString = packed array[1..255] of char;
      cStringPtr = ^cString;
      charPtr = ^byte;
      booleanPtr = ^byte;
 
   var
      addr: longintPtr;			{effective address}
      i: integer;			{index variable}
      l: longint;			{work variable for forming ptr val}
      max: integer;			{max # of visible lines}
      r: rect;				{port rectangle}
      r2: rect;				{for clearing to eol}
      ref: refPtr;			{for dereferencing pointers}
      str: pStringPtr;			{work string}
      vp: varPtr;			{for moveing thru var list}
      vpt: integer;			{vertival drawing point}

   begin {DrawContent}
   if currentProc <> nil then		{if there is anything to do then...}
      if currentProc^.vars <> nil then begin
	 GetPortRect(r); 		{get port info}
	 vp := currentProc^.vars;	{init variable entry pointer}
	 for i := 1 to currentProc^.topVar do {skip to top var in this display}
	    vp := vp^.next;
	 max := r.v2 div vHeight;	{set max # vars that can be displayed}
	 vpt := 8;			{set vertical disp}
	 new(str);			{get a work string}
	 while (max <> 0) and (vp <> nil) do begin
	    MoveTo(2,vpt);		{draw the var name}
	    DrawStringWidth(dswCondense+dswTruncRight, vp^.expr, 95);
	    r2.v1 := vpt-8;		{erase the old value}
	    r2.v2 := r2.v1+vHeight;
	    r2.h1 := 2+StringWidth(vp^.expr);
	    r2.h2 := 98;
	    if r2.h2 > r.h2-25 then r2.h2 := r.h2-25;
	    EraseRect(r2);
            addr := pointer(vp^.addr);	{find the effective address}
            ref := vp^.ref;
            while ref <> nil do begin
               addr := pointer(ord4(addr^) + ref^.offset);
               ref := ref^.next;
               end; {while}
	    MoveTo(98,vpt);		{draw the var value}
	    case varFormats(ord(vp^.vf) & $003F) of
	       i1: begin
                  i := bytePtr(addr)^;
                  if ord(vp^.vf) = $0040 then
                     if i & $0080 <> 0 then
                        i := i | $FF00;
                  str^ := cnvis(i);
                  end;
	       i2:
                  if ord(vp^.vf) = $0041 then begin
                     l := integerPtr(addr)^;
                     l := l & $0000FFFF;
                     str^ := cnvis(l);
                     end {if}
                  else
                     str^ := cnvis(integerPtr(addr)^);
	       i4:
                  if ord(vp^.vf) = $0042 then begin
                     l := longintPtr(addr)^;
                     str^ := '';
                     i := 0;
                     while (l < 0) or (l > 999999999) do begin
                        i := i+1;
                        l := l-1000000000;
                        end; {while}
                     if i <> 0 then
                        str^ := cnvis(i);
                     str^ := concat(str^, cnvis(l));
                     end {if}
                  else
                     str^ := cnvis(longintPtr(addr)^);
	       r4: str^ := cnvrs(realPtr(addr)^,1,0);
	       r8: str^ := cnvrs(doublePtr(addr)^,1,0);
	       r10: str^ := cnvrs(extendedPtr(addr)^,1,0);
	       cp: begin
	          str^ := cnvrs(compPtr(addr)^,1,1);
	          if compPtr(addr)^ = compPtr(addr)^ then
	             str^[0] := chr(ord(str^[0]) - 2);
	          end;
	       cStr: str^ := cStringPtr(addr)^;
	       pStr: str^ := pStringPtr(addr)^;
	       c1: str^ := chr(charPtr(addr)^);
	       b1: if bytePtr(addr)^ = 0 then str^ := 'false' else str^ := 'true';
	       p4,ptr4: begin
		  str^ := '';
		  l := ord4(addr);
		  Hex(str^,l>>24);
		  Hex(str^,l>>16);
		  Hex(str^,l>>8);
		  Hex(str^,l);
		  end;
	       otherwise: str^ := '(invalid expression)';
	       end; {case}
	    DrawStringWidth(dswCondense+dswTruncRight, str, r.h2-(98+25+1));
	    r2.h1 := 98+StringWidth(str);
	    r2.h2 := r.h2-25;
	    EraseRect(r2);
	    max := max-1;		{next variable}
	    vp := vp^.next;
	    vpt := vpt+vHeight;
	    end; {while}
	 r.v1 := vpt-8;			{clear to eos}
	 r.h2 := r.h2-25;
	 EraseRect(r);
	 dispose(str);			{get rid of work string}
	 end; {if}
   end; {DrawContent}


begin {DrawVariables}
if vrPtr <> nil then begin
   if vrHeaderChanged then begin
      vrHeaderChanged := false;		{note that the update has occurred}
      if not isUpdate then begin 	{redraw the info bar}
         StartInfoDrawing(r,vrPtr);
         VrInfo(r,0,vrPtr);
         EndInfoDrawing;
         end; {if}
      GetPortRect(r);			{erase the old contents}
      EraseRect(r);
      DrawContent;
      DrawControls(vrPtr);
      end {if}
   else if status <> go then		{draw the variables}
      DrawContent;
   end; {if}
end; {DrawVariables}


procedure DisposeVariable (vp: varPtr);

{ Dispose of a variable record and its dynamic contents		}
{								}
{ Parameters:							}
{    vp - variable to dispose of				}

var
   rp,rp2: refPtr;			{for disposing of reference list}

begin {DisposeVariable}
rp := vp^.ref;
while rp <> nil do begin
   rp2 := rp;
   rp := rp2^.next;
   dispose(rp2);
   end; {while}
dispose(vp^.expr);
dispose(vp);
end; {DisposeVariable}


procedure DisposeVars (vp: varPtr);

{ dispose of a list of variables				}
{								}
{ parameters:							}
{    vp - pointer to the first variable in the list		}

var
   vp2: varPtr;				{for disposing of variable list}

begin {DisposeVars}
while vp <> nil do begin
   vp2 := vp;
   vp := vp2^.next;
   DisposeVariable(vp2);
   end; {while}
end; {DisposeVars}


function CopyVars (vp: varPtr): varPtr;

{ make a copy of a list of variables				}
{								}
{ parameters:							}
{    vp - list of variables to copy				}
{								}
{ Returns: pointer to the first variable in the new list	}

var
   firstp,lastp: varPtr;		{head,tail of list}
   np: varPtr;				{new variable entry}

begin {CopyVars}
firstp := nil;
lastp := nil;
while vp <> nil do begin
   new(np);
   if firstp = nil then begin
      np^.last := nil;
      firstp := np;
      end {if}
   else begin
      np^.last := lastp;
      lastp^.next := np;
      end; {else}
   np^.next := nil;
   lastp := np;
   new(np^.expr);
   np^.expr^ := vp^.expr^;
   np^.vf := vp^.vf;
   np^.ref := nil;
   vp := vp^.next;
   end; {while}
CopyVars := firstp;
end; {CopyVars}


procedure SaveTemplate (proc: procInfoPtr);

{ Save the variable template from this procedure		}

var
   tp: templatePtr;			{work pointer}

begin {SaveTemplate}
tp := templateList;			{delete any existing template}
while tp <> nil do
   if tp^.name^ = proc^.name^ then begin
      if tp^.last = nil then
         templateList := tp^.next
      else
         tp^.last^.next := tp^.next;
      if tp^.next <> nil then
         tp^.next^.last := tp^.last;
      DisposeVars(tp^.vars);
      dispose(tp^.name);
      dispose(tp);
      tp := nil;
      end {if}
   else
      tp := tp^.next;
if proc^.vars <> nil then begin
   new(tp);				{create a new template entry}
   tp^.last := nil;
   tp^.next := templateList;
   if templateList <> nil then
      templateList^.last := tp;
   templateList := tp;
   new(tp^.name);
   tp^.name^ := proc^.name^;
   tp^.vars := CopyVars(proc^.vars);
   tp^.topVar := proc^.topVar;
   tp^.numVars := proc^.numVars;
   end; {if}        
end; {SaveTemplate}


function NamesEqual (var n1, n2: pString): boolean;

{ Case insensitive string compare for equality			}
{								}
{ Parameters:							}
{    n1, n2 - strings to compare				}

label 1;

var
   len: unsigned;			{length of the strings}
   i: unsigned;				{loop/index variable}

begin {NamesEqual}
len := ord(n1[0]);
NamesEqual := false;
if len = ord(n2[0]) then begin
   for i := 1 to len do
      if ToUpper(n1[i]) <> ToUpper(n2[i]) then
         goto 1;
   NamesEqual := true;
   end; {if}           
1: {early exit} ;
end; {NamesEqual}


function NextEntry (p: entryArrayPtr): entryArrayPtr;

{ Index to the next entry in the symbol table			}
{								}
{ Parameters:							}
{    p - pointer to the current entry				}
{								}
{ Returns: Pointer to the next entry				}

var
   format: integer;			{format code}

begin {NextEntry}
format := p^.format & $3F;
if format = 13 then
   p := pointer(ord4(p) + sizeof(entryArray))
else begin                  
   p := pointer(ord4(p) + (p^.numSubscripts+1)*sizeof(entryArray));
   if format = 11 then
      p := NextEntry(p)
   else if format = 12 then begin
      while p^.longAddr <> 0 do
         p := NextEntry(p);
      p := NextEntry(p);
      end; {else if}
   end; {else}
NextEntry := p;
end; {NextEntry}


procedure EvaluateCell (cell: varPtr; proc: procInfoPtr; flagErrors: boolean);

{ Evaluate the expression in a cell (sets effective addr)	}
{								}
{ Parameters:							}
{    cell - cell to evaluate					}
{    proc - procedure containing this cell			}
{    flagErrors - should errors be flagged with an alert?	}

var
   ap,ape: entryArrayPtr;		{for trapsing thru symbol table}
   done: boolean;			{loop termination test}
   i: unsigned;				{loop/index variable}
   name: pStringPtr;			{function name}
   ref,ref2: refPtr;			{work reference pointers}
   str: pStringPtr;			{expression string}


   procedure GetName (name, str: pStringPtr);

   { Get a name							}
   {								}
   { Parameters:						}
   {    name - pointer to a buffer in which to place the	}
   {        name						}
   {    str - string from which to remove the name		}

   var
      i: unsigned;			{loop/index variable}

   begin {GetName}
   i := 1;
   while not (str^[i] in [chr(13),'[',']','(',')',',','^','.','-','>']) do
      i := i+1;
   i := i-1;
   name^ := copy(str^, 1, i);
   delete(str^, 1, i);
   end; {GetName}


   procedure Reference (cell: varPtr; ap: entryArrayPtr;
      format, subscripts: integer; str: pStringPtr);

   { Handle variable dereferencing				}
   {								}
   { Parameters:						}
   {    cell - variable cell					}
   {    ap - current entry is symbol table			}
   {    format - current format					}
   {    subscripts - number of subscripts left to process	}
   {    str - remaining expression string			}

   var
      recycle: boolean;		{keep processing?}


      procedure ArrayRef (tc: char);

      { Handle an array dereference				}
      {								}
      { Parameters:						}
      {    tc - char to close the array				}

      var
         done: boolean;			{for loop termination test}
         isString: boolean;			{is this a c-string?}
         val: longint;			{array subscript/displacement}

      begin {ArrayRef}
      isString := false;
      if format = ord(cstr) then begin
         subscripts := 1;
         format := ord(c1);
         isString := true;
         end; {if}
      repeat
         Delete(str^, 1, 1);
         if subscripts = 0 then begin
            done := true;
            if flagErrors then
               FlagError(21, 0);
            end {if}
         else begin
            ap := pointer(ord4(ap) + sizeof(entryArray));
            val := 0;
            while str^[1] in ['0'..'9'] do begin
               val := val*10 + (ord(str^[1]) - ord('0'));
               Delete(str^, 1, 1);
               end; {while}
            if not isString then begin
               if (val < ap^.startVal) or (val > ap^.endVal) then begin
                  val := ap^.startVal;
                  if flagErrors then
                     FlagError(20, 0);
                  end; {if}
               val := (val - ap^.startVal)*ap^.size;
               end; {if}
            with cell^ do
               if ref = nil then
        	  addr := pointer(ord4(addr) + val)
               else
        	  ref^.offset := ref^.offset + val;
            subscripts := subscripts - 1;
            done := str^[1] <> ',';
            end; {else}
      until done;
      if str^[1] = tc then begin
         Delete(str^, 1, 1);
         recycle := true;
         end {if}
      else if tc = ')' then begin
         if flagErrors then
            FlagError(22, 0);
         end {else if}
      else begin
         if flagErrors then
            FlagError(23, 0);
         end; {else}
      end; {ArrayRef}                            


      procedure CheckFinal;

      { make sure the final reference is valid			}

      begin {CheckFinal}
      if format & $003F = ord(record1) then begin
         if flagErrors then
            FlagError(32, 0);
         end {if}
      else if subscripts <> 0 then begin
         if flagErrors then
            FlagError(19, 0);
         end {else if}
      else if format & $0080 <> 0 then
         format := ord(ptr4);
      cell^.vf := varFormats(format);
      end; {CheckFinal}


      procedure FieldRef;

      { Handle a field dereference operator (.)			}

      var
         done: boolean;		{loop termination test}
         name: pStringPtr;		{field name}

      begin {FieldRef}
      if format <> 12 then begin
         if flagErrors then
            FlagError(30, 0);
         end {if}
      else begin
         Delete(str^, 1, 1);
         new(name);
         GetName(name, str);
         ap := pointer(ord4(ap) + sizeof(entryArray));
         repeat
            if NamesEqual(name^, ap^.name^) then begin
               done := true;
               recycle := true;
               with cell^ do
        	  if ref = nil then
        	     addr := pointer(ord4(addr) + ord4(ap^.value))
        	  else
        	     ref^.offset := ref^.offset + ord4(ap^.value);
               format := ap^.format;
               subscripts := ap^.numSubscripts;
               end {if}
            else if ap^.longAddr <> 0 then begin
               done := false;
               ap := NextEntry(ap);
               end {else if}
            else begin
               done := true;
               if flagErrors then
                  FlagError(33, 0);
               format := ord(bad);
               end; {else}
         until done;
         dispose(name);
         end; {if}
      end; {FieldRef}


      procedure PointerRef;

      { Handle a pointer dereference operator (^)		}

      begin {PointerRef}
      Delete(str^, 1, 1);
      if format & $0080 <> 0 then begin
         format := format & $007F;
         new(ref);
         ref^.next := cell^.ref;
         cell^.ref := ref;
         ref^.offset := 0;
	 recycle := true;
         end {if}
      else if format = 11 then begin
         if subscripts <> 0 then
            if flagErrors then
               FlagError(19, 0);
         new(ref);
         ref^.next := cell^.ref;
         cell^.ref := ref;
         ref^.offset := 0;
         ap := pointer(ord4(ap) + sizeof(entryArray));
         subscripts := ap^.numSubscripts;
         format := ap^.format;
	 recycle := true;
         end {else if}
      else begin
         if flagErrors then
            FlagError(18, 0);
         format := ord(bad);
         end; {else}
      end; {PointerRef}


      procedure PointerFieldRef;

      { Handle a C-style -> operator				}

      begin {PointerFieldRef}
      if str^[2] <> '>' then begin
         if flagErrors then
            FlagError(31, 0);
         end {if}
      else begin
         str^[1] := '^';
         str^[2] := '.';
         recycle := true;
         end; {else}
      end; {PointerFieldRef}


   begin {Reference}
   repeat
      recycle := false;
      while format = 13 do begin
         ap := pointer(ord4(proc^.symbols)+ap^.numSubscripts);
         format := ap^.format;
         subscripts := ap^.numSubscripts;
         end; {while}
      case str^[1] of
	 '[':	ArrayRef(']');
	 '(':	ArrayRef(')');
	 '^':	PointerRef;
	 '.':	FieldRef;
	 '-':	PointerFieldRef;
	 otherwise:	CheckFinal;
         end; {case}
   until not recycle;
   end; {Reference}


begin {EvaluateCell}
new(name);				{allocate string buffers}
new(str);
while cell^.ref <> nil do begin		{dispose of old dereference list}
   ref := cell^.ref;
   cell^.ref := ref;
   dispose(ref);
   end; {while}
cell^.vf := bad;			{assume a bad expression}
str^ := concat(cell^.expr^, chr(13));	{form the expression line}
repeat
   i := pos(' ', str^);
   done := i = 0;
   if not done then
      Delete(str^, i, 1);
until done;
GetName(name, str);			{separate the name from any references}
with proc^ do begin
   ap := symbols;			{find the proper variable}
   ape := pointer(ord4(ap)+length);
   end; {with}
done := false;
repeat
   if ap = ape then begin		{no such entry}
      if flagErrors then
         FlagError(17, 0);
      DrawVariables(false);
      done := true;
      end {if}
   else if NamesEqual(ap^.name^, name^) then	begin
      done := true;			{fount it...}
      if ap^.longAddr = 0 then	{set up the address}
	 cell^.addr := pointer(proc^.DP+ord4(ap^.value))
      else
	 cell^.addr := pointer(ap^.value);
					{dereference the address}
      Reference(cell, ap, ap^.format, ap^.numSubscripts, str);
      end {else if}
   else
      ap := NextEntry(ap);		{move to the next entry}
until done; 
ref := cell^.ref;			{reverse the reference list}
if ref <> nil then begin
   cell^.ref := nil;
   while ref <> nil do begin
      ref2 := ref;
      ref := ref^.next;
      ref2^.next := cell^.ref;
      cell^.ref := ref2;
      end; {while}
   end; {if}
dispose(str);				{dispose of string buffers}
dispose(name);
end; {EvaluateCell}


procedure UseTemplate (proc: procInfoPtr);

{ Use an existing variables template, if there is one		}
{								}
{ Parameters:							}
{    proc - procedure to check					}

var
   done: boolean;			{loop termination test}
   tp: templatePtr;			{used to trace the template list}
   port: grafPortPtr;			{caller's port}
   vp: varPtr;				{used to trace the variable list}

begin {UseTemplate}
if vrPtr <> nil then begin
   port := GetPort;			{get caller's port}
   SetPort(vrPtr);
   tp := templateList;			{find a template}
   repeat
      done := tp = nil;
      if not done then
	 done := proc^.name^ = tp^.name^;
      if not done then
	 tp := tp^.next;
   until done;
   if tp <> nil then begin		{found one - use it}
      DisposeVars(proc^.vars);
      proc^.vars := CopyVars(tp^.vars);
      proc^.topVar := tp^.topVar;
      proc^.numVars := tp^.numVars;
      vp := proc^.vars;
      while vp <> nil do begin
	 EvaluateCell(vp, proc, false);
	 vp := vp^.next; 
	 end; {while}
      vrHeaderChanged := true;
      StartDrawing(vrPtr);
      DrawVariables(false);
      end; {if}
   SetPort(port);			{restore caller's port}
   end; {if}
end; {UseTemplate}


procedure AddGlobals (clength: integer; csymbols: entryArrayPtr);

{ add a procedure to the procedure list & make it current	}
{								}
{ Parameters:							}
{    clength - symbol table length				}
{    csymbols - ptr to symbol table				}

var
   gr: procInfoPtr;			{work pointer}
   hand: handle;			{symbol table handle}
   nlength: longint;			{new symbol table length}
   nsymbols: entryArrayPtr;		{new symbol table pointer}


   function GetGlobalsRecord: procInfoPtr;

   { Find the globals record, or create a new one		}
   {								}
   { Returns: Pointer to the record; nil for error		}

   label 1;

   var
      last,proc: procInfoPtr;		{work pointers}

   begin {GetGlobalsRecord}
   proc := procList;			{check for an existing record}
   if proc <> nil then begin
      while proc^.next <> nil do
         proc := proc^.next;
      if proc^.dp = 0 then
         goto 1;
      end; {if}
   last := proc;			{create a new record}
   new(proc);
   if proc <> nil then begin
      if last = nil then begin		{place it in the linked list}
         proc^.last := nil;
         procList := proc;
         end {if}
      else begin
         last^.next := proc;
         proc^.last := last;
         end; {else}
      proc^.next := nil;
      with proc^ do begin
         name := @'<globals>';		{set the name of the subroutine}
         length := 0;			{set the length of the symbol table}
         symbols := nil;		{set the symbol table pointer}
         dp := 0;			{set the diract page address}
         vars := nil;			{no variables are visible}
         topVar := 0;
         numVars := 0;
         end; {with}
      end; {if}
   1: GetGlobalsRecord := proc;
   end; {GetGlobalsRecord}


begin {AddGlobals}
gr := GetGlobalsRecord;			{make sure one exists}
if gr <> nil then begin
   nlength := (ord4(clength) & $0000FFFF) + (ord4(gr^.length) & $0000FFFF);
   if nlength > 65535 then
      FlagError(34, 0)
   else begin
      hand := NewHandle(nlength, UserID, $C010, nil);
      if ToolError <> 0 then
         OutOfMemory
      else begin
         nsymbols := entryArrayPtr(hand^);
         if gr^.length <> 0 then
            BlockMove(pointer(gr^.symbols), pointer(nsymbols), gr^.length);
         if clength <> 0 then
            BlockMove(pointer(csymbols), pointer(ord4(nsymbols)+gr^.length),
               clength);
         if gr^.symbols <> nil then begin
            hand := FindHandle(pointer(gr^.symbols));
            if hand <> nil then
               DisposeHandle(hand);
            end; {if}
         gr^.length := long(nlength).lsw;
         gr^.symbols := nsymbols;
         end; {else}
      end; {else}
   end; {if}
vrHeaderChanged := true;		{make sure we update the window}
end; {AddGlobals}


procedure AddProc (cname: pStringPtr; clength: integer; csymbols: entryArrayPtr;
   cDP: integer);

{ add a procedure to the procedure list & make it current	}
{								}
{ Parameters:							}
{    cname - procedure name					}
{    clength - symbol table length				}
{    csymbols - ptr to symbol table				}
{    cDP - stack frame addr					}

var
   proc: procInfoPtr;			{work pointer}

begin {AddProc}
new(proc);				{form a new work area}
with proc^ do begin
   last := nil;				{add it to the list}
   next := procList;
   if procList <> nil then
      procList^.last := proc;
   procList := proc;
   name := cname;			{set the name of the subroutine}
   length := clength;			{set the length of the subroutine}
   symbols := csymbols;			{set the symbol table pointer}
   dp := cDP;				{set the diract page address}
   vars := nil;				{no variables are visible}
   topVar := 0;
   numVars := 0;
   end; {with}
currentProc := proc;			{make this the current procedure}
vrHeaderChanged := true;
UseTemplate(proc);			{use any existing template}
end; {AddProc}


procedure RemoveProc;

{ remove the top procedure from the procedure list		}

var
   hand: handle;			{symbol table handle}
   proc: procInfoPtr;			{work pointer}
   vp,vp2: varPtr;			{for disposing of variable list}

begin {RemoveProc}
if procList <> nil then begin
   if currentProc = procList then begin {if the top proc is displayed, change  }
      currentProc := currentProc^.next; { the displayed proc		       }
      vrHeaderChanged := true;
      end; {if}
   if proc^.dp <> 0 then
      SaveTemplate(procList)		{record the variable template}
   else begin
      hand := FindHandle(proc^.symbols); {dispose of the global symbol table}
      if hand <> nil then
         DisposeHandle(hand);
      end; {else}
   DisposeVars(procList^.vars);		{delete the list of visible variables}
   proc := procList;			{remove the record}
   procList := proc^.next;
   if procList <> nil then
      procList^.last := nil;
   dispose(proc);
   end; {if}
end; {RemoveProc}

{------------------------------------------------------------------------------}

procedure GetString (str: pStringPtr; len: integer; h1,v1,h2,v2: integer);

{ get a string using line edit					}
{								}
{ Parameters:							}
{    str -							}
{    len -							}
{    h1,v1,h2,v2 - location of line edit box			}

var
   clen: integer;			{length if the initial text}
   destRect,viewRect: rect;		{line edit dest & view rectangles}
   done: boolean;			{loop termination test}
   event: eventRecord;			{last event returned in event loop}
   i: integer;				{loop variable}
   lh: leRecHndl;			{handle of the line edit record}
   p: point;				{work point}

begin {GetString}
destRect.h1 := h1; destRect.h2 := h2;	{allocate the edit record}
destRect.v1 := v1; destRect.v2 := v2;
viewRect.h1 := h1-4; viewRect.h2 := h2+8;
viewRect.v1 := v1-1; viewRect.v2 := v2+1;
EraseRect(viewRect);
FrameRect(viewRect);
viewRect.h2 := h2+4;
lh := LENew(destRect,viewRect,len);
LEActivate(lh);
clen := length(str^);			{set up initial text}
if clen <> 0 then begin
   LESetText(pointer(ord4(str)+1),clen,lh);
   LESetSelect(0,clen,lh);
   LEUpdate(lh);
   end; {if}

done := false;				{event loop}
repeat
   if GetNextEvent($002E,event) then
      case event.eventWhat of
	 mouseDownEvt: begin		{mouse down}
	    p := event.eventWhere;	{----------}
	    GlobalToLocal(p);		{need local coords for test}
	    if PtInRect(p,viewRect) then {if in edit box, do it; else beep}
	       LEClick(event,lh)
	    else
	       SysBeep;
	    end;
	 keyDownEvt,autoKeyEvt:		{all keys but return go to the editor}
	    if long(event.eventMessage).lsw = return then
	       done := true
	    else
	       LEKey(long(event.eventMessage).lsw,event.eventModifiers,lh);
	 otherwise: ;
	 end; {case}
   LEIdle(lh);
until done;

with lh^^ do begin
   for i := 1 to leLength do		{copy the string into the caller's area}
      str^[i] := leLineHandle^^[i];
   str^[0] := chr(leLength);
   end; {with}
LEDispose(lh);				{dipose of the line edit record}
StartDrawing(FrontWindow);		{erase the ugly box}
EraseRect(viewRect);
end; {GetString}


function GetAuxType (name: gsosInStringPtr): integer;

{ Read the auxiliary file type for a file			}
{								}
{ Parameters:							}
{    name - file name for the file to check			}
{								}
{ Returns: Least significant word of the auxiliary file type	}
{    for the file, or -1 for error				}

var
   giRec: getFileInfoOSDCB;		{for GetFileInfo call}

begin {GetAuxType}
GetAuxType := -1;
giRec.pcount := 4;
giRec.pathName := name;
GetFileInfoGS(giRec);
if ToolError = 0 then
   GetAuxType := long(giRec.auxType).lsw;
end; {GetAuxType}
   

function GetFileType (name: gsosInStringPtr): integer;

{ Read the file type for a file					}
{								}
{ Parameters:							}
{    name - file name for the file to check			}
{								}
{ Returns: File type for the file, or -1 for error		}

var
   giRec: getFileInfoOSDCB;		{for GetFileInfo call}

begin {GetFileType}
GetFileType := -1;
giRec.pcount := 4;
giRec.pathName := name;
GetFileInfoGS(giRec);
if ToolError = 0 then
   GetFileType := giRec.fileType;
end; {GetFileType}


procedure PrefixReset (name: gsosInStringPtr);

{ If the file is not GS/OS aware, restore prefixes 0-7		}
{								}
{ Parameters:							}
{    name - name of the file just executed			}

var
   aux: integer;			{Auxiliary file type}


   procedure SetP (oldp, newp: unsigned);

   { Set a GS/OS prefix to a ProDOS prefix, clearing the ProDOS	}
   { prefix.							}
   {								}
   { Parameters:						}
   {    oldp - ProDOS prefix number				}
   {    newp - GS/OS prefix number				}

   var
      gpRec: getPrefixOSDCB;		{for GetPrefix calls}
      p: gsosOutStringPtr;		{work prefix}

   begin {SetP}
   new(p);
   p^.maxSize := osMaxSize;
   gpRec.pcount := 2;
   gpRec.prefixNum := oldp;
   gpRec.prefix := p;
   GetPrefixGS(gpRec);
   if ToolError <> 0 then begin
      gpRec.prefix := @p^.theString;
      gpRec.prefixNum := newp;
      SetPrefixGS(gpRec);
      p^.theString.size := 0;
      gpRec.prefixNum := oldp;
      SetPrefixGS(gpRec);
      end; {if}
   dispose(p);
   end; {SetP}


begin {PrefixReset}
aux := GetAuxType(name);		{only do this for non-GS/OS aware progs}
if (aux & $FF00 <> $DB00) or (not odd(aux)) then begin
   SetP(0, 8);
   SetP(1, 9);
   SetP(2, 13);
   SetP(3, 14);
   SetP(4, 15);
   SetP(5, 16);
   SetP(6, 17);
   SetP(7, 18);
   end; {if}
end; {PrefixSetup}


function PrefixSetup (name: gsosInStringPtr): boolean;

{ If the file is not GS/OS aware, set up prefixes 0-7		}
{								}
{ Parameters:							}
{    name - name of the file to be executed			}
{								}
{ Returns: True if successful, else false			}

label 1;

var
   aux: integer;			{Auxiliary file type}
   i: 0..7;				{loop/index variable}
   p: array[0..7] of gsosOutStringPtr;	{prefix array}
   spRec: getPrefixOSDCB;		{for SetPrefix calls}
   tError: integer;			{tool error; reported by Get}


   procedure Get (var p: gsosOutStringPtr; pnum: unsigned);

   { Read a prefix						}
   {								}
   { Parameters:						}
   {    p - pointer in which to place the prefix path		}
   {    pnum - prefix number					}

   var
      gpRec: getPrefixOSDCB;		{for GetPrefix calls}

   begin {Get}
   new(p);
   p^.maxSize := osMaxSize;
   gpRec.pcount := 2;
   gpRec.prefixNum := pnum;
   gpRec.prefix := p;
   GetPrefixGS(gpRec);
   if ToolError <> 0 then
      tError := ToolError;
   end; {Get}


begin {PrefixSetup}
for i := 0 to 7 do			{initialize pointers so we know what's used}
   p[i] := nil;
PrefixSetup := true;			{assume success}
aux := GetAuxType(name);		{only do this for non-GS/OS aware progs}
if (aux & $FF00 <> $DB00) or (not odd(aux)) then begin
   tError := 0;				{read the prefixes}
   Get(p[0], 8);
   Get(p[1], 9);
   Get(p[2], 13);
   Get(p[3], 14);
   Get(p[4], 15);
   Get(p[5], 16);
   Get(p[6], 17);
   Get(p[7], 18);
   if tError <> 0 then begin		{check for read error}
      FlagError(29, tError);
      PrefixSetup := false;
      end {if}
   else begin
      for i := 0 to 7 do		{check the lengths}
	 if p[i]^.theString.size > 64 then begin
            FlagError(28, 0);
            PrefixSetup := false;
            goto 1;
            end; {if}
      spRec.pcount := 2;		{set the lower prefixes}
      for i := 0 to 7 do begin
         spRec.prefixNum := i;
         spRec.prefix := @p[i]^.theString;
         SetPrefixGS(spRec);
         end; {for}
      end; {if}
   end; {if}
1:
for i := 0 to 7 do			{dispose of dynamic memory}
   if p[i] <> nil then
      dispose(p[i]);
end; {PrefixSetup}


procedure SaveFileName;

{ save the name of the current file				}

var
   fp: nameRecPtr;

begin {SaveFileName}
if sourcePtr <> nil then begin
   new(fp);
   fp^.next := nameList;
   fp^.name := sourcePtr^.pathName;
   nameList := fp;
   end; {if}
end; {SaveFileName}


procedure RestoreFileName;

{ restore the last used source file				}

var
   fp: nameRecPtr;

begin {RestoreFileName}
if nameList <> nil then begin
   fp := nameList;
   nameList := fp^.next;
   if fp <> nil then
      SetSourceWindow(@fp^.name);
   dispose(fp);
   end; {if}
end; {RestoreFileName}

{------------------------------------------------------------------------------}

procedure CreateSpecialControls (wp: grafPortPtr; var grow,vScroll: ctlRecHndl;
   value,param1,param2: integer);

{ create and draw a set of controls for one of the special	}
{ windows							}
{								}
{ Parameters:							}
{    wp - window containing the controls 			}
{    grow - grow box						}
{    vScroll - vertical scroll bar				}
{    value -							}
{    param1 -							}
{    param2 -							}

var
   r: rect;				{current rectangle}

begin {CreateSpecialControls}
GetPortRect(r);				{get the size of the window}
r.h1 := r.h2-24; 			{create a grow box}
r.h2 := r.h2+2;
r.v1 := r.v2-13;
r.v2 := r.v2+1;
grow := NewControl(wp,r,nil,0,0,0,0,pointer($08000000),0,nil);
r.v1 := 0;				{create vertical scroll bar}
r.v2 := r.v2-13;
vScroll := NewControl(wp,r,nil,3,value,param1,param2,pointer($06000000),0,nil);
DrawControls(wp);
end; {CreateSpecialControls}


procedure ProfileCall (pname: pStringPtr);

{ add a call to the profile list 				}
{								}
{ Parameters:							}
{    pname -							}

label 1;

var
   pp: profilePtr;			{work pointer}
   sp: subPtr;				{work pointer}

begin {ProfileCall}
pp := profileLink;			{find an old entry}
while pp <> nil do begin
   if pp^.namePtr = pname then goto 1;
   pp := pp^.next;
   end; {while}
new(pp); 				{none there - create a new one}
with pp^ do begin
   heartbeats := 0;
   calls := 0;
   name := pname^;
   namePtr := pname;
   next := profileLink;
   end; {with}
profileLink := pp;
1:
new(sp); 				{add to call stack}
with sp^ do begin
   ptr := pp;
   next := subLink;
   end; {with}
subLink := sp;
pp^.calls := pp^.calls+1;		{update # of calls}
end; {ProfileCall}


procedure ProfileReport;

{ write the results of the profile				}

var
   percent: integer;			{% * 10}
   pp: profilePtr;			{work pointer}
   sp: subPtr;				{work pointer}
   total: longint;			{total # of heartbeats}

begin {ProfileReport}
while subLink <> nil do begin		{dump any subroutine links}
   sp := subLink;
   subLink := sp^.next;
   dispose(sp);
   end; {while}
pp := profileLink;			{compute total heartbeats}
total := 0;
while pp <> nil do begin
   total := pp^.heartbeats+total;
   pp := pp^.next;
   end; {while}
if total = 0 then total := 1;
while profileLink <> nil do begin	{write the report}
   with profileLink^ do begin
      percent := ord(heartbeats*1000 div total);
      writeln(name,calls:21-length(name),
	 heartbeats:11,percent div 10:6,'.',percent mod 10:1);
      end; {with}
   pp := profileLink;
   profileLink := pp^.next;
   dispose(pp);
   end; {while}
end; {ProfileReport}


procedure ProfileReturn;

{ remove a call from the profile list				}

var
   sp: subPtr;				{work pointer}

begin {ProfileReturn}
if subLink <> nil then begin
   sp := subLink;
   subLink := sp^.next;
   dispose(sp);
   end; {if}
end; {ProfileReturn}


procedure DoAutoSave;

{ if requiested, save any files that have changed		}

var
   lCurrentPtr: buffPtr; 		{local copy of currentPtr}

begin {DoAutoSave}
if autoSave then begin
   Compact;
   lCurrentPtr := currentPtr;
   currentPtr^ := currentFile;
   currentPtr := filePtr;
   while currentPtr <> nil do begin
      if currentPtr^.changed then
	 if currentPtr^.isFile then begin
	    currentFile := currentPtr^;
	    SaveFile(6);
	    Compact;
	    currentPtr^ := currentFile;
	    end; {if}
      currentPtr := currentPtr^.next;
      end; {while}
   currentPtr := lCurrentPtr;
   currentFile := currentPtr^;
   Expand;
   end; {if}
end; {DoAutoSave}


procedure GetShellWindow;

{ find and activate a shell window				}

label 1;

var
   osName: gsosInString;		{path name}
   osNamePtr: gsosInStringPtr;		{path name pointer}
   sPtr: pStringPtr;			{resource string pointer}

begin {GetShellWindow}
sourcePtr := currentPtr; 		{save the source file}
if currentPtr <> nil then begin
   Compact;
   currentPtr^ := currentFile;
   end; {if}
shellPtr := filePtr;			{try to find and activate an old file}
while shellPtr <> nil do begin
   if shellPtr^.language = -1 then goto 1;
   shellPtr := shellPtr^.next;
   end; {while}
sPtr := GetPString(104+base);		{none: open a new shell file}
osNamePtr := PStringToOSString(sPtr);
osName := osNamePtr^;
OpenNewWindow(320,25,320,75,@osName);
FreePString(104+base);
sPtr := GetPString(108+base);
currentFile.pathName.theString := concat('8:', sPtr^);
currentFile.pathname.size := length(currentFile.pathName.theString);
currentFile.fileName := concat(' ', sPtr^, ' ');
FreePString(108+base);
currentFile.language := -1;
currentPtr^ := currentFile;
SetWTitle(@currentPtr^.fileName,currentFile.wPtr);
RemoveWindow(currentFile.wPtr);
AddWindow2(currentFile.wPtr);
shellPtr := currentPtr;
if sourcePtr = nil then
   sourcePtr := shellPtr;
if FindActiveFile(sourcePtr^.wPtr) then ;
SelectWindow(currentFile.wPtr);
CheckWindow(currentFile.wPtr);
DrawControls(currentFile.wPtr);
DrawControls(shellPtr^.wPtr);
1:
Expand;
if sourcePtr <> shellPtr then begin	{get the source file ready}
   if currentFile.selection then begin
      currentFile.selection := false;
      DrawScreen;
      end; {if}
   MoveToStart;
   currentFile.cursorColumn := 0;
   currentPtr^ := currentFile;
   end; {if}
shellWindow := shellPtr^.wPtr;
end; {GetShellWindow}


procedure GetInfo;

{ retrieve info passed back by the compiler or linker		}

begin {GetInfo}
with liDCB do begin
   pcount := 11;
   lsFile.maxSize := osMaxSize;
   ldFile.maxSize := osMaxSize;
   lnamesList.maxSize := osMaxSize;
   liString.maxSize := osMaxSize;
   sFile := @lsFile;
   dFile := @ldFile;
   namesList := @lnamesList;
   iString := @liString;
   end; {with}
GetLInfoGS(liDCB);
end; {GetInfo}


procedure SetPrefix16 (var fn: gsosInString);

{ expand file name to full path name using prefix 16		}
{								}
{ Parameters:							}
{    fn - file name to append to prefix 16			}

var
   gpDCB: getPrefixOSDCB;		{GetPrefix DCB}
   i: unsigned;				{loop/index variable}
   prefix16: gsosOutString;		{prefix}

begin {SetPrefix16}
gpDCB.pcount := 2;
gpDCB.prefixNum := 16;
gpDCB.prefix := @prefix16;
prefix16.maxSize := osMaxSize;
GetPrefixGS(gpDCB);
for i := 1 to fn.size do
   if prefix16.theString.size <= osBuffLen then begin
      prefix16.theString.size := prefix16.theString.size+1;
      prefix16.theString.theString[prefix16.theString.size] := fn.theString[i];
      end; {if}
fn := prefix16.theString;
end; {SetPrefix16}


function IsOurWindow (wp: grafPortPtr): boolean;

{ check to see if wp is in our window list			}
{								}
{ Parameters:							}
{    wp - window to check					}
{								}
{ Returns: true if the window is ours, else false		}

label 1;

var
   wrp: windowRecordPtr; 		{work window record pointer}

begin {IsOurWindow}
IsOurWindow := false;
wrp := windowList;
while wrp <> nil do begin
   if wrp^.owp = wp then begin
      IsOurWindow := true;
      goto 1;
      end; {if}
   wrp := wrp^.next;
   end; {while}
1:
end; {IsOurWindow}


procedure DisposeWindowList;

{ dispose of the window list and any windows that are not in it }

var
   wp: grafPortPtr;			{window ptr for scanning open windows}
   wrp: windowRecordPtr; 		{work window record pointer}

begin {DisposeWindowList}
wp := pointer(GetFirstWindow);		{close any user windows still on the   }
while wp <> nil do begin 		{ desktop			       }
   if IsOurWindow(wp) then
      wp := GetNextWindow(wp)
   else begin
      CloseWindow(wp);
      wp := pointer(GetFirstWindow);
      end {else}
   end; {while}
while windowList <> nil do begin 	{dispose of the list of windows}
   wrp := windowList^.next;
   dispose(windowList);
   windowList := wrp;
   end; {while}
end; {DisposeWindowList}


procedure NewWindowList;

{ build a list of all of the windows on the desktop		}

var
   wp: grafPortPtr;			{current window pointer}
   wrp: windowRecordPtr; 		{work window record pointer}

begin {NewWindowList}
wp := pointer(GetFirstWindow);		{get first window}
while wp <> nil do begin 		{add windows until there are no more}
   new(wrp);
   with wrp^ do begin
      owp := wp;
      next := windowList;
      end; {with}
   windowList := wrp;
   wp := GetNextWindow(wp);
   end; {while}
end; {NewWindowList}


procedure RunAProgram;

{ run a program							}

var
   frontFile: grafPortPtr;		{front window before executing}
   i: integer;				{loop variable}
   r: rect;				{for erasing graphics window}

begin {RunAProgram}
if vrPtr <> nil then begin		{update the variables window}
   vrHeaderChanged := true;
   StartDrawing(vrPtr);
   DrawVariables(false);
   end; {if}
GetShellWindow;				{get an output window}
if graphicsWindowOpen then begin 	{if available, enable graphics window}
   StartDrawing(grPtr);
   GetPortRect(r);
   EraseRect(r);
   DrawControls(grPtr);
   StartDrawing(currentFile.wPtr);
   end; {if}
oldVector5 := GetVector(5);		{set up for debugger}
SetVector(5,@CopProcessor);
lineNumber := 0;
SetMenuState(execMenu);
StartConsole;				{allow interupts again}
sourcePtr := nil;			{no active source file}
frontFile := FrontWindow;		{save the initial source file}
if profile then				{install the profiler}
   InstallProfiler;
InstallIntercepts;			{install the tool intercepts}
executing := true;			{executing a program, now}
if length(executeCommandLine) <> 0 then {set up the command line}
   commandLine := concat('BYTEWRKS', executeCommandLine)
else
   commandLine := '';
					{set up the prefixes and run the program}
if GetFileType(@ldFile.theString) in [EXE,S16] then begin
   if PrefixSetup(@ldFile.theString) then begin
      LoadAndCall(@ldFile.theString,false,true);
      PrefixReset(@ldFile.theString);
      end; {if}
   end {if}
else
   LoadAndCall(@ldFile.theString,false,true);
commandLine := '';			{everyone else uses this...}
executing := false;			{not executing a program, now}
RemoveIntercepts;			{remove the tool intercepts}
MarkLine(lineNumber,ord(' '));		{remove any arrow}
if profile then begin			{remove the profiler}
   ProfileReport;
   RemoveProfiler;
   end; {if}
StopConsole;				{need to do interupt sensitive stuff}
Expand;
SetMenuState(nullMenu);			{fix menus}
while procList <> nil do 		{update the variables window}
   RemoveProc;
currentProc := nil;
vrHeaderChanged := true;
if vrPtr <> nil then begin
   StartDrawing(vrPtr);
   DrawVariables(false);
   end; {if}
while nameList <> nil do 		{destroy file name list}
   RestoreFileName;
SetVector(5,oldVector5); 		{clean up from debugger}
if frontFile <> nil then
   if FindActiveFile(frontFile) then begin
      StartDrawing(frontFile);
      CheckMenuItems;
      end; {if}
end; {RunAProgram}


procedure Link (comp: compKind; kind: compileKind; flags: integer);

{ link a file							}
{								}
{ Parameters:							}
{    comp -							}
{    kind -							}
{    flags - SetLInfo lops flags				}

var
   giDCB: getFileInfoOSDCB;		{for changing file type}
   sfDCB: setFileInfoOSDCB;		{for changing file type}
   siDCB: SetLInfoDCBGS;		{for setting language info}
   msg: string[128];			{for note message}

begin {Link}
WaitCursor;				{this takes time...}
if linkRec = nil then begin		{get a name for the linker}
   new(linkRec);
   linkRec^.theString := 'LINKER';
   linkRec^.size := length(linkRec^.theString);
   SetPrefix16(linkRec^);
   end; {if}
siDCB.pcount := 11;			{set up the language parameters}
siDCB.sFile := @lsFile.theString;
siDCB.dFile := @ldFile.theString;
siDCB.namesList := @lnamesList.theString;
siDCB.iString := @liString.theString;
siDCB.merr := 0;
siDCB.merrf := 0;
siDCB.lops := flags;
if linkSave then
   siDCB.kFlag := liDCB.kFlag
else
   siDCB.kFlag := 0;
if flags & 2 <> 0 then begin		{link the program}
   siDCB.mFlags := $00000201;		{-w, auto keep name used}
   if kind = memory then
      siDCB.pFlags := $00080000		{+m}
   else
      siDCB.pFlags := $00000000;
   if linkList then
      siDCB.pFlags := siDCB.pFlags | $00100000	{+l}
   else
      siDCB.mFlags := siDCB.mFlags | $00100000;	{-l}
   if linkSymbol then
      siDCB.pFlags := siDCB.pFlags | $00002000	{+s}
   else
      siDCB.mFlags := siDCB.mFlags | $00002000;	{-s}
   if linkSave then
      siDCB.pFlags := siDCB.pFlags | $00200000;	{+k}
   siDCB.org := liDCB.org;
   SetLInfoGS(siDCB);
   if PrefixSetup(linkRec) then begin
      InstallIntercepts;
      LoadAndCall(linkRec,true,false);
      RemoveIntercepts;
      PrefixReset(linkRec);
      end; {if}
   end; {if}
GetInfo;  
StopConsole;
ResetCursor;
with liDCB do
   if merrf > merr then begin
      FlagError(14, 0);
      if sourcePtr <> nil then
         if FindActiveFile(sourcePtr^.wPtr) then ;
      end {if}
   else begin
      giDCB.pcount := 4;		{set the file type}
      giDCB.pathName := @ldFile.theString;
      GetFileInfoGS(giDCB);
      if ToolError = 0 then begin
	 case fileKind of
	    kS16: sfDCB.fileType := S16;
	    kCDA: sfDCB.fileType := CDA;
	    kNDA: sfDCB.fileType := NDA;
            otherwise: sfDCB.fileType := EXE;
	    end; {case}
         sfDCB.pcount := 4;
	 sfDCB.pathName := @ldFile.theString;
         sfDCB.access := giDCB.access;
         if fileKind in [kS16,kEXE] then
            sfDCB.auxType := $00DB00
               | (ord(gsosAware)
                  | (ord(deskAware) << 1)
                  | (ord(messageAware) << 2))
         else
            sfDCB.auxType := 0;
	 SetFileInfoGS(sfDCB);
	 end; {if}
					{execute the program}
      if (lops & 4 <> 0) and linkExecute then begin
         if sourcePtr <> nil then
	    if FindActiveFile(sourcePtr^.wPtr) and (comp = thisWindow) then
	       with currentFile do begin
		  exeName := ldFile.theString; {record the new executabe file}
		  changesSinceCompile := false;
		  end; {with}
	 HiliteMenu(false,7);
	 HiliteMenu(false,8);
	 RunAProgram;			{execute the program}
	 end {if}
      else
         if sourcePtr <> nil then
	    if FindActiveFile(sourcePtr^.wPtr) then ;
      end; {else}
CheckMenuItems;
end; {Link}


procedure Compile (comp: compKind; kind: compileKind; flags: integer);

{ compile a file 						}
{								}
{ Parameters:							}
{    comp -							}
{    kind -							}
{    flags -							}

label 1,2,3,4;

const
   alertID = 3005;			{alert string resource ID}
   alertID2 = 3006;			{another alert string resource ID}
   alertID3 = 3007;			{another alert string resource ID}

var          
   button: integer;			{button pushed}
   changes: boolean;			{has file changed since last compile?}
   cp: buffPtr;				{work buffer pointer}
   giDCB: getFileInfoOSDCB;		{DCB for Get_File_Info}
   language: integer;			{language of source file}
   lComp: compKind;			{local copy of comp parameter value}
   lp: languageRecPtr;			{work pointer for scanning lang. list}
   msg: string[128];			{error message string}
   siDCB: SetLInfoDCBGS;		{for setting language info}
   sArr: array[0..1] of pStringPtr;	{substitution array}

   pathName: gsosInString;		{path name of the compiler}


   procedure FastFiles (action: integer);

   { add or remove files from the FastFile list			}
   {								}
   { Parameters: 						}
   {	action - fastfile action code				}
   
   var
      ffDCB: fastFileDCBGS;		{DCB for file load}
      i: 1..8;				{loop/index variable}
      lCurrentPtr: buffPtr;		{local copy of currentPtr}

   begin {FastFiles}
   Compact;				 {save the current file}
   lCurrentPtr := currentPtr;
   currentPtr^ := currentFile;
   currentPtr := filePtr;
   while currentPtr <> nil do begin	{loop over all but the shell window}
      if currentPtr <> shellPtr then begin
	 currentFile := currentPtr^;	{compact it}
	 Compact;
	 with currentFile do		{make sure there are at least 3 }
	    if ord4(buffEnd)-ord4(buffStart) < 3 then begin  { free bytes...}
	       Expand;
	       GrowBuffer;
	       Compact;
	       end; {if}
	 HUnlock(pointer(currentFile.buffHandle)); {let the file move}
	 ffDCB.action := action; 	{add it to the FastFile list}
	 with ffDCB do begin
            pcount := 14;
	    flags := 0;
	    fileHandle := pointer(currentFile.buffHandle);
	    pathName := @currentFile.pathName;
	    access := $C3;
	    if currentFile.language = 0 then
	       fileType := TXT
	    else
	       fileType := SRC;
	    auxType := currentFile.language;
	    storageType := 1;
            for i := 1 to 8 do
	       createDate[i] := 0;
	    modDate := createDate;
            option := nil;
	    fileLength :=
               ord4(currentFile.gapStart)-ord4(currentFile.buffStart);
	    end; {with}
	 FastFileGS(ffDCB);		{add/delete the file}
	 currentPtr^ := currentFile;
	 end; {if}
      currentPtr := currentPtr^.next;
      end; {while}
   currentPtr := lCurrentPtr;
   currentFile := currentPtr^;
   if currentPtr = shellPtr then 	{make the shell file current}
      Expand;
   end; {FastFiles}


begin {Compile}
WaitCursor;				{this takes time...}
DoAutoSave;				{save changed files}
lComp := comp;				{record the lComp value}
liDCB.kFlag := 1;
if comp = thisWindow then
   with liDCB do begin			{set up keep name now so it}
      if kind = scan then begin		{ can be modified for multi}
	 ldFile.theString.size := 0;	{ lingual compiles	   }
	 kFlag := 0;
	 end; {if}
      end; {with}
4:
if lComp = thisWindow then		{determine the language}
   language := currentFile.language
else begin
   giDCB.pcount := 4;
   giDCB.pathName := @lsFile.theString;
   GetFileInfoGS(giDCB);
   if ToolError = 0 then
      language := long(giDCB.auxType).lsw
   else begin
      sArr[0] := OSStringToPString(@lsFile.theString);
      ResetCursor;
      button := AlertWindow($0005, @sArr, base + alertID);
      goto 1;
      end;
   end; {else}
lp := languages; 			{find the language path name}
while lp <> nil do begin
   if lp^.number = language then begin
      pathName.theString := lp^.name;
      pathName.size := length(pathName.theString);
      SetPrefix16(pathName);
      giDCB.pcount := 4;
      giDCB.pathName := @pathName;
      GetFileInfoGS(giDCB);
      if ToolError = 0 then
	 goto 2;
      end; {if}
   lp := lp^.next;
   end; {while}
FlagError(15, 0);
goto 1;
2:
siDCB.pcount := 11;			{set up the language parameters}
siDCB.sFile := @lsFile.theString;
siDCB.dFile := @ldFile.theString;
siDCB.namesList := @lnamesList.theString;
siDCB.iString := @liString.theString;
siDCB.merr := 0;
siDCB.merrf := 0;
siDCB.lops := flags;
siDCB.kFlag := liDCB.kFlag;
siDCB.mFlags := $00000201;		{-w, auto keep name used}
with siDCB do begin
   if kind = memory then
      pFlags := $08081000		{+e +t +m}
   else
      pFlags := $08001000;		{+e +t}
   if compileList then
      pFlags := pFlags | $00100000	{+l}
   else
      mFlags := mFlags | $00100000;	{-l}
   if compileSymbol then
      pFlags := pFlags | $00002000	{+s}
   else
      mFlags := mFlags | $00002000;	{-s}
   if compileDebug then
      pFlags := pFlags | $10000000;	{+d}
   end; {with}
siDCB.org := 0;
SetLInfoGS(siDCB);
GetShellWindow;				{initialize the console output driver}
WaitCursor;
StartConsole;
					{set up the prefixes and run the program}
if PrefixSetup(@pathName) then begin
   FastFiles(4);			{place files in FastFile list}
   compiling := true;
   InstallIntercepts;			{install the tool intercepts}
   LoadAndCall(@pathName,true,false);	{load and call the compiler}
   RemoveIntercepts;			{remove the tool intercepts}
   compiling := false;			{remove files from FastFile list}
   FastFiles(6);
   PrefixReset(@pathName);		{reset GS/OS prefixes}
   end {if}
else
   loadSucceeded := false;
if loadSucceeded then			{check the progress}
   GetInfo
else begin
   liDCB.lops := 0;
   compileLink := false;
   end; {else}
if liDCB.merrf > liDCB.merr then begin
   StopConsole;
   if sourcePtr <> nil then
      if FindActiveFile(sourcePtr^.wPtr) then ;
					{find the file where the error occurred}
   if OSStringsEqual(@currentFile.pathName, @lsFile.theString) then begin
      cp := filePtr;
      while cp <> nil do begin
	 if OSStringsEqual(@cp^.pathName, @lsFile.theString) then begin
	    if FindActiveFile(cp^.wPtr) then
	       goto 3;
	    end; {if}
	 cp := cp^.next;
	 end; {while}
      end; {if}
3:
   if OSStringsEqual(@currentFile.pathName, @lsFile.theString) then begin
      Expand;				{position the cursor in the source file}
      currentFile.selection := false;
      with currentFile do begin
	 cursor := pointer(ord4(buffStart)+liDCB.org);
	 if ord4(cursor) >= ord4(gapStart) then
	    cursor := pointer(ord4(cursor)+ord4(pageStart)-ord4(gapStart));
	 if ord4(cursor) >= ord4(buffEnd) then
	    cursor := pointer(ord4(buffEnd)-1);
	 StartDrawing(wPtr);
	 end; {with}
      FindCursor;
      FollowCursor;
      sArr[0] := OSStringToPString(@lnamesList.theString);
      ResetCursor;
      button := AlertWindow($0005, @sArr, base + alertID2);
      end {if}
   else begin
      Expand;
      sArr[0] := OSStringToPString(@lnamesList.theString);
      sArr[1] := OSStringToPString(@lsFile.theString);
      ResetCursor;
      button := AlertWindow($0005, @sArr, base + alertID3);
      end; {else}
   end {if}
else if odd(liDCB.lops) then begin
   lComp := diskFile;
   goto 4;
   end {else}
else if liDCB.lops & 6 = 0 then begin
   StopConsole;
   if sourcePtr <> nil then
      if FindActiveFile(sourcePtr^.wPtr) then ;
   end {else if}
else if compileLink then begin		{link & go}
   liDCB.sFile := @ldFile;
   eFile.maxSize := osMaxSize;
   liDCB.dFile := @eFile;
   Link(lcomp,kind,liDCB.lops);
   end {else}
else
   StopConsole;
1:
Expand;
CheckMenuItems;
ResetCursor;
end; {Compile}


procedure InvalidateCompiles;

{ make all compiles invalid					}

var
   cp: buffPtr;				{work buffer pointer}

begin {InvalidateCompiles}
cp := filePtr;
while cp <> nil do begin
   cp^.changesSinceCompile := true;
   cp := cp^.next;
   end; {while}
currentFile.changesSinceCompile := true;
end; {InvalidateCompiles}

{------------------------------------------------------------------------------}

procedure CloseGraphics;

{ close the graphics window					}

begin {CloseGraphics}
if grPtr <> nil then begin
   CloseWindow(grPtr);
   grPtr := nil;
   graphicsWindowOpen := false;
   end; {if}
end; {CloseGraphics}


procedure DoCompile {kind: compileKind; flags: integer; menuNum: integer};

{ do a compile/link/execute sequence				}
{								}
{ Parameters:							}
{    kind - kind of compile					}
{    flags -							}
{    menuNum -							}

var
   changes: boolean;			{changes since last compile?}
   i: integer;				{index variable}


   procedure AddOSStr (var os: gsosInString; ps: pStringPtr);

   { Add a p-string to a GS/OS input string			}
   {								}
   { Parameters:						}
   {    os - GS/OS input string					}
   {    ps - pointer to p-String				}

   var
      i: unsigned;			{loop/index variable}

   begin {AddOSStr}
   for i := 1 to length(ps^) do
      if os.size <= osBuffLen then begin
	 os.size := os.size+1;
	 os.theString[os.size] := ps^[i];
	 end; {if}
   end; {AddOSStr}


   function FileExists (fileName: gsosInStringPtr): boolean;

   { See if a file exists on an available disk			}
   {								}
   { Parameters: 						}
   {	fileName - file to check 				}
   {								}
   { Returns: true if the file exists, false if not		}

   var
      giDCB: getFileInfoOSDCB;		{for making sure the file exists}

   begin {FileExists}
   giDCB.pcount := 4;
   giDCB.pathName := fileName;
   GetFileInfoGS(giDCB);
   FileExists := ToolError = 0;
   end; {FileExists}


begin {DoCompile}
if not currentFile.isFile then
   FlagError(25, 0)
else if not FileExists(currentFile.pathName) then
   FlagError(16, 0)
else begin
					{if the exe file is gone, recompile}
   if not FileExists(currentFile.exeName) then
      currentFile.changesSinceCompile := true;
   if currentFile.changesSinceCompile	{compile the program}
      then begin
      if currentFile.selection then begin
	 currentFile.selection := false;
	 DrawScreen;
	 end; {if}
      lsFile.theString := currentFile.pathName;
      ldFile := lsFile;
      i := ldFile.theString.size;
      while (not (ldFile.theString.theString[i] in ['.',':'])) and (i > 0) do
	 i := i-1;
      if (i > 0) and (ldFile.theString.theString[i] = '.') then begin
	 ldFile.theString.size := i-1;
	 eFile := ldFile;
	 end {if}
      else begin
         eFile := ldFile;
         AddOSStr(eFile.theString, @'.exe');
         AddOSStr(ldFile.theString, @'.obj');
	 end; {else}
      lnamesList.theString.size := 0;
      liString.theString.size := 0;
      Compile(thisWindow,kind,flags);
      HiliteMenu(false,menuNum);
      end {if}
   else if (flags & 4) <> 0 then begin	   {run an existing program}
      ldFile.theString := currentFile.exeName;
      HiliteMenu(false,menuNum);
      RunAProgram;
      end; {else}
   end; {else}
end; {DoCompile}


procedure DoCompile2;

{ get compile options						}

const
   resID 	= 8000;			{resource ID}
   cmpSet	= 1;			{control IDs}
   cmpCompile	= 2;
   cmpCancel	= 3;
   cmpDefaults	= 16;
   cmpTitle1	= 4;
   cmpLine1	= 5;
   cmpTitle2	= 6;
   cmpLine2	= 7;
   cmpTitle3	= 8;
   cmpLine3	= 9;
   cmpTitle4	= 10;
   cmpLine4	= 11;
   cmpTitle5	= 17;
   cmpLine5	= 18;
   cmpCheck1	= 12;
   cmpCheck2	= 13;
   cmpCheck3	= 14;
   cmpCheck4	= 15;

var
   dEvent: eventRecord;			{last event returned by DoModalWindow}
   gpRec: getPrefixOSDCB;		{GetPrefixGS record}
   gtPtr: grafPortPtr;			{dialog box pointer}
   i: 0..maxint;			{loop/index variable}
   osStr: gsosOutString;		{for getting/setting prefix}
   part: 0..maxint;			{dialog item hit}
   str: pString;			{work string; for editLine items}


   procedure SetOptions;

   { Set options returned by the dialog				}

   var
      spRec: getPrefixOSDCB;		{SetPrefixGS record}

   begin {SetOptions}
   GetLETextByID(gtPtr, cmpLine5, str);
   spRec.pcount := 2;
   spRec.prefixNum := 16;
   osStr.theString.theString := str;
   osStr.theString.size := length(str);
   spRec.prefix := @osStr.theString;
   SetPrefixGS(spRec);
   if ToolError <> 0 then
      FlagError(5, ToolError);
   compileList := 0 <> GetCtlValueByID(gtPtr, cmpCheck1);
   compileSymbol := 0 <> GetCtlValueByID(gtPtr, cmpCheck2);
   compileDebug := 0 <> GetCtlValueByID(gtPtr, cmpCheck3);
   compileLink := 0 <> GetCtlValueByID(gtPtr, cmpCheck4);
   end; {SetOptions}


   procedure DoTheCompile;

   { Handle a hot on the Compile button				}

   var
      lCompileList: boolean;		{copies of global variables saved}
      lCompileSymbol: boolean;
      lCompileDebug: boolean;
      lCompileLink: boolean;
      op: gsosInStringPtr;		{work pointer}

   begin {DoTheCompile}
   GetLETextByID(gtPtr, cmpLine1, str);
   op := PStringToOSString(str);
   lsFile.theString := op^;
   GetLETextByID(gtPtr, cmpLine2, str);
   op := PStringToOSString(str);
   ldFile.theString := op^;
   eFile := ldFile;
   GetLETextByID(gtPtr, cmpLine3, str);
   op := PStringToOSString(str);
   lnamesList.theString := op^;
   GetLETextByID(gtPtr, cmpLine4, str);
   op := PStringToOSString(str);
   liString.theString := op^;
   if lsFile.theString.size = 0 then
      FlagError(4, 0)
   else begin
      lCompileList := compileList;
      lCompileSymbol := compileSymbol;
      lCompileDebug := compileDebug;
      lCompileLink := compileLink;
      SetOptions;
      CloseWindow(gtPtr);
      gtPtr := nil;
      Compile(diskFile, disk,
         (ord(linkExecute) << 2) | (ord(compileLink) << 1) | 1);
      compileList := lCompileList;
      compileSymbol := lCompileSymbol;
      compileDebug := lCompileDebug;
      compileLink := lCompileLink;
      end; {else}
   end; {DoTheCompile}


begin {DoCompile2}
gtPtr := NewWindow2(nil, 0, @DrawControlWindow, nil, $02, base+resID, rWindParam1);
if gtPtr <> nil then begin
   SetCtlValueByID(ord(compileList), gtPtr, cmpCheck1);
   SetCtlValueByID(ord(compileSymbol), gtPtr, cmpCheck2);
   SetCtlValueByID(ord(compileDebug), gtPtr, cmpCheck3);
   SetCtlValueByID(ord(compileLink), gtPtr, cmpCheck4);
   gpRec.pcount := 2;
   gpRec.prefixNum := 16;
   gpRec.prefix := @osStr;
   osStr.maxSize := osBuffLen+4;
   GetPrefixGS(gpRec);
   str[0] := chr(osStr.theString.size);
   for i := 1 to osStr.theString.size do
      str[i] := osStr.theString.theString[i];
   SetLETextByID(gtPtr, cmpLine5, str);
   MakeThisCtlTarget(GetCtlHandleFromID(gtPtr, cmpLine1));
   
   while gtPtr <> nil do begin
      ResetCursor;
      repeat
	 part := ord(DoModalWindow(dEvent, nil, nil, nil, $C01A));
      until part in [cmpSet,cmpCompile,cmpCancel,cmpDefaults];
      ResetCursor;

      if part = cmpSet then begin
	 SetOptions;
	 InvalidateCompiles;
	 CloseWindow(gtPtr);
	 gtPtr := nil;
	 end {if}
      else if part = cmpCompile then
	 DoTheCompile
      else if part = cmpDefaults then begin
	 SetOptions;
	 RestorePrefix9;
	 Sleep(PStringToOSString(@'9/PRIZM.CONFIG'));
	 CloseWindow(gtPtr);
	 gtPtr := nil;
	 end {else if}
      else begin
	 CloseWindow(gtPtr);
	 gtPtr := nil;
         end; {else}
      end; {while}
   end; {if}
end; {DoCompile2}


procedure DoExecute;

{ Execute a file from disk					}

const
   resID = 103;				{prompt string resource ID}

var
   op: ^gsosOutStringPtr;		{work pointer}
   reply: replyRecord5_0;		{reply from SFO}
   tl: typeList5_0;			{list of file types}

begin {DoExecute}
tl.numEntries := 4;
with tl.fileAndAuxTypes[1] do begin flags := $8000; fileType := EXE; end;
with tl.fileAndAuxTypes[2] do begin flags := $8000; fileType := S16; end;
with tl.fileAndAuxTypes[3] do begin flags := $8000; fileType := SYS; end;
with tl.fileAndAuxTypes[4] do begin flags := $8000; fileType := NDA; end;
reply.nameVerb := 3;
reply.pathVerb := 3;
SFGetFile2 (120, 40, 2, resID+base, nil, tl, reply);
Null0;
if reply.good <> 0 then begin
   op := pointer(reply.pathRef);
   ldFile := op^^;
   GetShellWindow;
   status := executeMode;
   RunAProgram;
   Expand;
   DisposeHandle(pointer(reply.nameRef));
   DisposeHandle(pointer(reply.pathRef));
   end; {if}
end; {DoExecute}


procedure DoExecuteOptions;

{ Set execute options						}

const
   resID 	= 7000;			{resource ID}
   excOK	= 1;			{control IDs}
   excCancel	= 2;
   excTitle2	= 4;
   excTitle3	= 5;
   excLinePatt	= 6;
   excGo	= 7;
   excTrace	= 8;
   excStep	= 9;
   excLine2	= 11;
   excLine3	= 12;
   
var
   dEvent: eventRecord;			{last event returned by DoModalWindow}
   gtPtr: grafPortPtr;			{dialog box pointer}
   part: 0..maxint;			{dialog item hit}

begin {DoExecuteOptions}
gtPtr := NewWindow2(nil, 0, @DrawControlWindow, nil, $02, base+resID, rWindParam1);
if gtPtr <> nil then begin
   if executeMode = step then
      SetCtlValueByID(1, gtPtr, excStep)
   else if executeMode = trace then
      SetCtlValueByID(1, gtPtr, excTrace)
   else
      SetCtlValueByID(1, gtPtr, excGo);
   SetLETextByID(gtPtr, excLinePatt, executeCommandLine);
   ResetCursor;
   repeat
      part := ord(DoModalWindow(dEvent, nil, nil, nil, $C01A));
   until part in [excOK, excCancel];
   ResetCursor;

   if part = excOK then begin
      GetLETextByID(gtPtr, excLinePatt, executeCommandLine);
      if GetCtlValueByID(gtPtr, excStep) <> 0 then
         executeMode := step
      else if GetCtlValueByID(gtPtr, excTrace) <> 0 then
         executeMode := trace
      else
         executeMode := go;
      end; {if}
   CloseWindow(gtPtr);
   end; {if}
end; {DoExecuteOptions}


procedure DoGraphics;

{ Show or hide the graphics window				}

begin {DoGraphics}
ShowHide(graphicsWindowOpen,grPtr);
SendBehind(pointer(-2),grPtr);
if FrontWindow <> nil then
   SelectWindow(FrontWindow);
end; {DoGraphics}


procedure DoLink;

{ get link options						}

const
   resID 	= 9000;			{resource ID}
   lnkSet	= 1;
   lnkLink	= 2;
   lnkCancel	= 3;
   lnkDefaults	= 16;
   lnkTitle1	= 4;
   lnkLine1	= 5;
   lnkTitle2	= 6;
   lnkLine2	= 7;
   lnkTitle3	= 17;
   lnkLine3	= 18;
   lnkCheck1	= 8;
   lnkCheck2	= 9;
   lnkCheck3	= 10;
   lnkCheck4	= 11;
   lnkRadio1	= 12;
   lnkRadio2	= 13;
   lnkRadio3	= 14;
   lnkRadio4	= 15;
   lnkDLine1	= 19;
   lnkDLine2	= 20;
   lnkDLine3	= 21;
   lnkCheck5	= 22;
   lnkCheck6	= 23;
   lnkCheck7	= 24;

var
   dEvent: eventRecord;			{last event returned by DoModalWindow}
   gpRec: getPrefixOSDCB;		{GetPrefixGS record}
   gtPtr: grafPortPtr;			{dialog box pointer}
   i: 0..maxint;			{loop/index variable}
   lnkRadio: 0..maxint;			{radio button to set}
   osStr: gsosOutString;		{for getting/setting prefix}
   part: 0..maxint;			{dialog item hit}
   str: pString;			{work string; for editLine items}


   procedure SetOptions;

   { Set options returned by the dialog				}

   var
      spRec: getPrefixOSDCB;		{SetPrefixGS record}

   begin {SetOptions}
   GetLETextByID(gtPtr, lnkLine3, str);
   spRec.pcount := 2;
   spRec.prefixNum := 13;
   osStr.theString.theString := str;
   osStr.theString.size := length(str);
   spRec.prefix := @osStr.theString;
   SetPrefixGS(spRec);
   if ToolError <> 0 then
      FlagError(7, ToolError);
   linkList := 0 <> GetCtlValueByID(gtPtr, lnkCheck1);
   linkSymbol := 0 <> GetCtlValueByID(gtPtr, lnkCheck2);
   linkExecute := 0 <> GetCtlValueByID(gtPtr, lnkCheck3);
   linkSave := 0 <> GetCtlValueByID(gtPtr, lnkCheck4);
   gsosAware := 0 <> GetCtlValueByID(gtPtr, lnkCheck5);
   messageAware := 0 <> GetCtlValueByID(gtPtr, lnkCheck6);
   deskAware := 0 <> GetCtlValueByID(gtPtr, lnkCheck7);
   if GetCtlValueByID(gtPtr, lnkRadio1) <> 0 then
      fileKind := kEXE
   else if GetCtlValueByID(gtPtr, lnkRadio2) <> 0 then
      fileKind := kS16
   else if GetCtlValueByID(gtPtr, lnkRadio3) <> 0 then
      fileKind := kCDA
   else
      fileKind := kNDA;
   end; {SetOptions}


   procedure DoTheLink;

   { Handle a hot on the Link button				}

   var
      lLinkList: boolean;		{copies of global variables saved}
      lLinkSymbol: boolean;
      lLinkExecute: boolean;
      lLinkSave: boolean;
      lFileKind: fileKindType;
      op: gsosInStringPtr;		{work pointer}

   begin {DoTheLink}
   GetLETextByID(gtPtr, lnkLine1, str);
   op := PStringToOSString(str);
   lsFile.theString := op^;
   GetLETextByID(gtPtr, lnkLine2, str);
   op := PStringToOSString(str);
   ldFile.theString := op^;
   eFile := ldFile;
   if lsFile.theString.size = 0 then
      FlagError(6, 0)
   else begin
      lLinkList := linkList;
      lLinkSymbol := linkSymbol;
      lLinkExecute := linkExecute;
      lLinkSave := linkSave;
      lFileKind := fileKind;
      SetOptions;
      CloseWindow(gtPtr);

      liDCB.merr := 0;
      liDCB.merrf := 0;
      liDCB.kFlag := 3;
      status := go;
      GetShellWindow;
      StartConsole;
      Link(diskFile,disk,(ord(linkExecute)<<2) | 2);
      linkList := lLinkList;
      linkSymbol := lLinkSymbol;
      linkExecute := lLinkExecute;
      linkSave := lLinkSave;
      fileKind := lFileKind;
      end; {else}      
   end; {DoTheLink}


   procedure EnableChecks (fk: fileKindType);

   { Enable or disable file dependent check boxes		}
   {								}
   { Parameters:						}
   {    fk - file kind						}

   var
      hilite: unsigned;			{control hilight state}

   begin {EnableChecks}
   if fk in [kEXE,kS16] then
      hilite := 0
   else
      hilite := 255;
   HiliteCtlByID(hilite, gtPtr, lnkCheck5);
   HiliteCtlByID(hilite, gtPtr, lnkCheck6);
   HiliteCtlByID(hilite, gtPtr, lnkCheck7);
   end; {EnableChecks}


begin {DoLink}
gtPtr := NewWindow2(nil, 0, @DrawControlWindow, nil, $02, base+resID, rWindParam1);
if gtPtr <> nil then begin
   SetCtlValueByID(ord(linkList), gtPtr, lnkCheck1);
   SetCtlValueByID(ord(linkSymbol), gtPtr, lnkCheck2);
   SetCtlValueByID(ord(linkExecute), gtPtr, lnkCheck3);
   SetCtlValueByID(ord(linkSave), gtPtr, lnkCheck4);
   SetCtlValueByID(ord(gsosAware), gtPtr, lnkCheck5);
   SetCtlValueByID(ord(messageAware), gtPtr, lnkCheck6);
   SetCtlValueByID(ord(deskAware), gtPtr, lnkCheck7);
   EnableChecks(fileKind);
   case fileKind of
      kS16: lnkRadio := lnkRadio2;
      kCDA: lnkRadio := lnkRadio3;
      kNDA: lnkRadio := lnkRadio4;
      otherwise: lnkRadio := lnkRadio1;
      end; {case}
   SetCtlValueByID(1, gtPtr, lnkRadio);
   gpRec.pcount := 2;
   gpRec.prefixNum := 13;
   gpRec.prefix := @osStr;
   osStr.maxSize := osBuffLen+4;
   GetPrefixGS(gpRec);
   str[0] := chr(osStr.theString.size);
   for i := 1 to osStr.theString.size do
      str[i] := osStr.theString.theString[i];
   SetLETextByID(gtPtr, lnkLine3, str);
   MakeThisCtlTarget(GetCtlHandleFromID(gtPtr, lnkLine1));
   
   ResetCursor;
   repeat
      part := ord(DoModalWindow(dEvent, nil, nil, nil, $C01A));
      if part = lnkRadio1 then
         EnableChecks(kEXE)
      else if part = lnkRadio2 then
         EnableChecks(kS16)
      else if part = lnkRadio3 then
         EnableChecks(kCDA)
      else if part = lnkRadio4 then
         EnableChecks(kNDA);
   until part in [lnkSet,lnkLink,lnkCancel,lnkDefaults];
   ResetCursor;

   if part = lnkSet then begin
      SetOptions;
      InvalidateCompiles;
      CloseWindow(gtPtr);
      end {if}
   else if part = lnkLink then
      DoTheLink
   else if part = lnkDefaults then begin
      SetOptions;
      RestorePrefix9;
      Sleep(PStringToOSString(@'9/PRIZM.CONFIG'));
      CloseWindow(gtPtr);
      end {else if}
   else
      CloseWindow(gtPtr);
   end; {if}
end; {DoLink}


procedure DoVariablesMouseDown {h,v: integer};

{ handle a mouse down event in the variables window		}
{								}
{ Parameters:							}
{    h,v - position in local coordinates 			}

var
   cell: varPtr;			{variable cell pointer}
   cellV: unsigned;			{vertical position of the cell}


   procedure UpdateWindow;

   { Update the window after changing the number of variables	}

   var
      port: grafPortPtr;		{grafPort on entry}
      r: rect;				{for resizing the scroll bar}

   begin {UpdateWindow}
   port := GetPort;
   SetPort(vrPtr);
   GetPortRect(r);
   with currentProc^ do
      SetCtlParams(numVars+1,r.v2 div vHeight,vrVScroll);
   vrHeaderChanged := true;
   DrawVariables(false);
   SetPort(port);
   end; {UpdateWindow}


   function NewVariable: varPtr;

   { Allocate a new variable					}
   {								}
   { Returns: Pointer to new variable, inserted in the symbol	}
   {    table and with a name field allocated			}

   var
      vp,vp2: varPtr;			{for creating a variable table entry}

   begin {NewVariable}
   new(vp);
   if currentProc^.vars = nil then begin
      vp^.last := nil;
      currentProc^.vars := vp;
      end {if}
   else begin
      vp2 := currentProc^.vars;
      while vp2^.next <> nil do
	 vp2 := vp2^.next;
      vp^.last := vp2;
      vp2^.next := vp;
      end; {else}
   vp^.next := nil;
   new(vp^.expr);
   vp^.expr^ := '';
   vp^.ref := nil;
   NewVariable := vp;
   with currentProc^ do 		{update the variable count}
      numVars := numVars+1;
   end; {NewVariable}


   procedure ShowAllVariables;

   { Display all available scalar variables			}

   var
      ap,ape: entryArrayPtr;		{for trapsing thru symbol table}


      procedure AddEntry (ap: entryArrayPtr);                    

      { Add an entry to the current procedure display		}
      {								}
      { Parameters:						}
      {    ap - entry to add					}

      var
	 vp: varPtr;			{for creating a variable table entry}

      begin {AddEntry}
      vp := NewVariable;		{allocate a variable record}
      with vp^ do begin
	 new(expr);			{set the addr of the name}
	 expr^ := ap^.name^;
	 vf := varFormats(ord(ap^.format)); {set the variable format}
	 if ap^.longAddr = 0 then	{set up the address}
	    addr := pointer(currentProc^.DP+ord4(ap^.value))
	 else
	    addr := pointer(ap^.value);
         ref := nil;
	 end; {with}
      end; {AddEntry}

             
      function EntryExists (ap: entryArrayPtr): boolean;

      { See if a variable is already in the display		}
      {								}
      { Parameters:						}
      {    ap - entry to check for				}

      var
	 vp: varPtr;			{for tracing variables list}


      begin {EntryExists}
      EntryExists := false;
      vp := currentProc^.vars;
      while vp <> nil do begin
         if NamesEqual(ap^.name^, vp^.expr^) then begin
            EntryExists := true;
            vp := nil;
            end {if}
         else
            vp := vp^.next;
         end; {while}
      end; {EntryExists}


   begin {ShowAllVariables}
   with currentProc^ do begin		{set up to scan the symbol table}
      ap := symbols;
      ape := pointer(ord4(ap)+length);
      end; {with}
   while ord4(ap) < ord4(ape) do begin
      if ap^.numSubscripts = 0 then
         if ap^.format in [0..10,$40..$42] then
            if not EntryExists(ap) then
               AddEntry(ap);
      ap := NextEntry(ap);
      end; {while}
   UpdateWindow;			{update the display}
   end; {ShowAllVariables}


   procedure FindCell (v: integer; var cell: varPtr; var cellV: unsigned);

   { Find the cell to modify					}
   {								}
   { Parameters:						}
   {    v - vertical mouse down position			}
   {    cell - (output) cell to edit				}
   {    cellV - cell vertical position				}

   var
      i: unsigned;			{loop/index variable}
      vp: varPtr;			{for tracing variables list}

   begin {FindCell}
   with currentProc^ do begin
      vp := vars;
      for i := 1 to topVar do
	 vp := vp^.next;
      end; {with}
   i := v div vHeight;
   cellV := 0;
   if vp <> nil then
      while (i <> 0) and (vp <> nil) do begin
	 vp := vp^.next;
	 cellV := cellV+1;
	 i := i-1;
	 end; {while}
   if vp = nil then
      vp := NewVariable;
   cell := vp;
   cellV := cellV*vHeight;
   end; {FindCell}


begin {DoVariablesMouseDown}
if v < 0 then begin			{mouse down in info bar}
   if h < 15 then begin
      if currentProc^.last <> nil then begin
	 currentProc := currentProc^.last;
	 vrHeaderChanged := true;
	 DrawVariables(false);
	 end; {if}
      end {if}
   else if h < 30 then begin
      if currentProc^.next <> nil then begin
	 currentProc := currentProc^.next;
	 vrHeaderChanged := true;
	 DrawVariables(false);
	 end {if}
      end {else if}
   else if h < 45 then begin
      ShowAllVariables;
      DrawVariables(false);
      end; {else if}
   end {if}
else if currentProc <> nil then begin	{do mouse down in content region}
   FindCell(v, cell, cellV);		{find the cell to modify}
   GetString(cell^.expr,255,4,cellV,160,cellV+10); {get the new string}
   if length(cell^.expr^) <> 0 then
      EvaluateCell(cell, currentProc, true) {find the type, address}
   else begin
      if cell^.last = nil then		{no string - dispose of the record}
         currentProc^.vars := cell^.next
      else
         cell^.last^.next := cell^.next;
      if cell^.next <> nil then
         cell^.next^.last := cell^.last;
      with currentProc^ do
         numVars := numVars-1;
      DisposeVariable(cell);
      end; {else}
   UpdateWindow;			{update the display}
   end; {else if}
end; {DoVariablesMouseDown}


procedure DoVariablesScroll {part: integer};

{ handle a scroll bar event in the variables window		}

var
   r: rect;				{variable port rect}
   rows: integer;			{# rows in window}

begin {DoVariablesScroll}
if currentProc <> nil then begin
   StartDrawing(vrPtr);
   GetPortRect(r);
   rows := r.v2 div vHeight;
   with currentProc^ do begin
      if part = 5 then			{up one line}
	 topVar := topVar-1
      else if part = 6 then		{down one line}
	 topVar := topVar+1
      else if part = 7 then		{up one page}
	 topVar := topVar-rows
      else if part = 8 then		{down one page}
	 topVar := topVar+rows
      else if part = 129 then		{thumb action}
	 topVar := GetCtlValue(vrVScroll);
      if topVar < 0 then topVar := 0;
      if numVars-rows+1 < topVar then topVar := numVars-rows+1;
      SetCtlValue(topVar,vrVScroll);
      end; {with}
   DrawVariables(false);
   end; {if}
end; {DoVariablesScroll}


procedure RedoVrWindow;

{ redo the variables window                                     }

var
   r: rect;                             {current port rectangle}

begin {RedoVrWindow}
DisposeControl(vrGrow);                 {dispose of old controls}
DisposeControl(vrVScroll);
GetPortRect(r);                         {erase old controls}
EraseRect(r);
if currentProc <> nil then begin
   with currentProc^ do
      CreateSpecialControls(vrptr,vrGrow,vrVScroll,topVar,r.v2 div vHeight,
         numVars+1);
  end {if}
else
   CreateSpecialControls(vrPtr,vrGrow,vrVScroll,0,20,10);
DrawVariables(false);                   {draw the variables}
end; {RedoVrWindow}


procedure SetSourceWindow {sourceName: gsosInStringPtr};

{ Change the source window to the named window			}
{								}
{ Parameters:							}
{    sourceName - source window name				}

label 1;

begin {SetSourceWindow}
sourcePtr := filePtr;
while sourcePtr <> nil do begin
   if OSStringsEqual(@sourcePtr^.pathName, sourceName) then
      if FindActiveFile(sourcePtr^.wPtr) then begin
	 currentPtr^ := currentFile;
	 goto 1;
	 end; {if}
   sourcePtr := sourcePtr^.next;
   end; {while}
1:
end; {SetSourceWindow}

{$DataBank+}

procedure UpdateGrWindow;

{ update the graphics window					}

var
   r: rect;				{current rectangle}

begin {UpdateGrWindow}
DisposeControl(grGrow);
GetPortRect(r);
r.h1 := r.h2-24;
r.h2 := r.h2+2;
r.v1 := r.v2-13;
r.v2 := r.v2+1;
grGrow := NewControl(grPtr,r,nil,0,0,0,0,pointer($08000000),0,nil);
DrawControls(grPtr);
end; {UpdateGrWindow}


procedure UpdateVrWindow;

{ update the variables window                                   }

begin {UpdateVrWindow}
DrawVariables(true);                    {draw the variables}
end; {UpdateVrWindow}

{$DataBank-}       

end.

{$append 'run.asm'}
