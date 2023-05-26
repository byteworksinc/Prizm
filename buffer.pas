{$optimize 7}
{-----------------------------------------------------------------------------}
{									      }
{  Buffer Management							      }
{									      }
{  This unit provides the primitives needed to manipulate the edit buffer.    }
{  When appropriate, it makes calls to the Display unit to update the	      }
{  display.  Creation of text windows is also handled.			      }
{									      }
{  The edit buffer is a contiguous area of memory of any length.  Its	      }
{  structure, when expanded for editing, is:				      }
{									      }
{	^	|---------|	<-- buffEnd				      }
{	|	| text	  |						      }
{	|	|---------|	<-- pageStart				      }
{   buffSize	| empty	  |						      }
{	|	|---------|	<-- gapStart				      }
{	|	| text	  |						      }
{	v	|---------|	<-- buffStart				      }
{									      }
{  The display shows lines starting at the line pointed to by pageStart.      }
{  As the screen scrolls, lines move from one end of the buffer, through the  }
{  gap, to the other end.  Thus, only one line is moved in memory when the    }
{  screen is scrolled, and at most one screen is moved to insert or delete a  }
{  character.								      }
{									      }
{  by Mike Westerfield							      }
{  January 1988								      }
{									      }
{  Copyright 1988							      }
{  Byte Works, Inc.							      }
{									      }
{-----------------------------------------------------------------------------}

unit Buffer;

interface

{$segment 'Buffer'}

uses Common, QuickDrawII, EventMgr, WindowMgr, ControlMgr, MenuMgr, DialogMgr,
   ORCAShell, MemoryMgr, ScrapMgr, GSOS, ResourceMgr;

{$LibPrefix '0/obj/'}

uses PCommon;

const
   chWidth		 = 8;		{width of a character}
   chHeight		 = 8;		{height of a character}

   infoHeight		 = 12;		{height of the information bar}
   hScrollHeight 	 = 14;		{height of horiz. scroll bar}
   vScrollWidth		 = 26;		{width of vertical scroll bar}

   blackPen		 = 0;		{available pen colors}
   purplePen		 = 1;
   greenPen		 = 2;
   whitePen		 = 3;

type
   charPtr = ^byte;			{pointer to a character}
   charHandle = ^charPtr;		{character handle}
   proString = string[64];		{ProDOS file name string}
   proStringPtr = ^pString;		{pointer to file name}
   rulerType = array[0..255] of byte;	{tab line}
   statusType = (step,trace,go); 	{execution status}
   string31 = string[31];		{file name type}
   string33 = string[33];		{padded (with spaces) file name type}
   fileKindType = (kEXE,kS16,kCDA,kNDA); {type of file to create}

   undoPtr = ^undoRecord;		{pointer to an undo record}
   undoRecord = record
      next: undoPtr;			{next record in stack}
      insertChars: longint;		{# chars to insert}
      insertPos: longint;		{disp of first char past those inserted}
      insertCol: integer;		{column at start of new characters}
      deleteChars: longint;		{# chars deleted}
      deletePos: longint;		{disp to insert at during an undo}
      deleteHandle: charHandle;		{handle of delete buffer}
      deleteSize: longint;		{size of the delete buffer}
      end;

   buffPtr = ^buffRec;			{pointer to buffer record}
   buffRec = record			{all of the information about a buffer}
      wPtr: grafPortPtr; 		{pointer to the window}
      vScroll,hScroll,grow: ctlRecHndl; {control handles}

      buffHandle: charHandle;		{handle of the buffer}
      buffStart,buffEnd: charPtr;	{start, end of the buffer}
      gapStart: charPtr; 		{first free byte in gap}
      pageStart: charPtr;		{first character on the display}
      buffSize: longint; 		{size of buffer, in bytes}
      expanded: boolean; 		{tells if the buffer is expanded}

      isFile: boolean;			{is there an existing file?}
      fileName: string33;		{file name}
      pathName: gsosInString;		{path name of the file}
      changed: boolean;			{has the file changed since saving?}

      cursor: charPtr;			{points to char cursor is on or before}
      cursorColumn: integer;		{screen position of cursor}
      cursorRow: longint;
      width,height: integer;		{screen width, height, in characters}
      maxHeight: integer;		{height of main & split screen}
      numLines: longint; 		{# lines in the file}
      topLine: longint;			{top line on the screen}
      leftColumn: integer;		{leftmost column on display}
      dispFromTop: integer;		{disp from top of first line}

      select: charPtr;			{if selection, this is the end of the
					 selected text - cursor is the other}
      selection: boolean;		{is there an active selection?}

      splitScreen: boolean;		{is the screen split?}
      topLineAlt: longint;		{line # of top line on alt screen}
      heightAlt: integer;		{height of alternate screen}
      vScrollAlt: ctlRecHndl;		{alt screen scroll bar}
      dispFromTopAlt: integer;		{disp from top in pixels}
      splitScreenRect: rect;		{split screen control location}

      showRuler: boolean;		{is the ruler visible?}
      ruler: rulerType;			{ruler - 1 -> tab stop; 0 -> no code}
      newDebug: boolean;		{true for new debug characters, false for old}

      insert: boolean;			{insert? (or overstrike)}
      autoReturn: boolean;		{return to first non-blank?}
      language: integer; 		{language number}

      last,next: buffPtr;		{links}

      changesSinceCompile: boolean;	{changes since last compile?}
      exeName: gsosInString;		{executable file name}

      undoList: undoPtr; 		{top of undo stack}

      verticalMove: boolean;		{was the last key a vertical move?}
      vCursorColumn: 0..maxint;		{cursorColumn before vertical move}
      end;
 
   searchString = packed array[0..255] of char; {search/replace string}
   searchStringPtr = ^searchString;

var
   currentFile: buffRec; 		{front window}
   currentPtr: buffPtr;			{pointer to current record}
   sourcePtr: buffPtr;			{pointer to source file being debugged}
   filePtr: buffPtr;			{head of file buffer list}
 
   cursorVisible: boolean;		{is the cursor on?}
   lastHeartBeat: longint;		{heartbeat at last cursor change}
 
   busy: boolean;			{flag to disable interupt updates}
   disableScreenUpdates: boolean;	{should the screen be updated?}
 
   compiling: boolean;			{are (fast)files set for a compile?}
   status: statusType;			{execution status}
   executing: boolean;			{are we executing a program?}
 
					{These variables are saved and restored}
					{as user-definable defaults.  They must}
					{remain here, IN ORDER.		       }
					{--------------------------------------}
   autoSave: boolean;			{save files before compile?}
   compileList: boolean; 		{l flag}
   compileSymbol: boolean;		{s flag}
   compileDebug: boolean;		{d flag}
   compileLink: boolean; 		{link after compile?}
   linkList: boolean;			{l flag}
   linkSymbol: boolean;			{s flag}
   linkSave: boolean;			{save file after link?}
   linkExecute: boolean; 		{execute after link?}
   fileKind: fileKindType;		{type of file to create}
   profile: boolean;			{doing a profile?}

{-----------------------------------------------------------------------------}

procedure Blink;

{ blink the cursor						}


procedure ChangeSize (h,v: integer; update: boolean);

{ change the size of the current window				}
{								}
{ Parameters:							}
{    h,v - new size						}
{    update -							}


procedure Compact;

{ Compact an expanded buffer					}


procedure CopySelection;

{ copy selected text to the scrap				}


procedure CreateControls (portRect: rectPtr);

{ create a set of controls for a window with the given size	}
{								}
{ Parameters:							}
{    portRect - size of the window				}


procedure DeleteSelection;

{ remove selected text from the file				}


procedure DoDeleteToEOL;

{ delete from the cursor to the end of the line			}


procedure DoSetClearMark (ch: integer);

{ set or clear auto go or break point status from a block of	}
{ text								}
{								}
{ Parameters:							}
{    ch - character to set					}


procedure DoUndo;

{ undo the last change						}


procedure DrawLine (line: integer);

{ draw one line on the screen					}
{								}
{ Parameters:							}
{    line - line to draw 					}


procedure DrawMark (ch, v, dispFromTop: integer); extern;

{ Draw the debug arrow (or other character)			}
{								}
{ Parameters:							}
{    ch - character to draw					}
{    v - vertical cursor position				}
{    dispFromTop - disp from top of screen			}


procedure DrawOneScreen (w,h,dispFromTop,left: integer;
   startChar,maxChar: charPtr; wp: grafPortPtr; tabs: rulerType); extern;

{ Redraw one part of the screen					}
{								}
{ Parameters:							}
{    w,h - width, height of the screen, in characters		}
{    dispFromTop - # pixels to space down for first line 	}
{    left - leftmost column on display				}
{    startChar - pointer to first char on the screen		}
{    maxChar - pointer to one past the last valid character	}
{    wp - pointer to window to draw in				}
{    tabs - tab stops						}


procedure DrawRuler (var r: rect; infoRefCon: longint; wPtr: grafPortPtr); extern;

{ ruler drawing routine						}
{								}
{ Parameters:							}
{    r - pointer to enclosing rect				}
{    infoRefCon - wInfoRefCon value				}
{    wPtr - pointer to window					}


procedure DrawScreen;

{ redraw the entire screen					}


procedure DrawSplitScreenControl (r: rect; splitScreen: boolean);

{ draw the split screen control					}
{								}
{ Parameters:							}
{    r - split screen control location				}
{    splitScreen - is the screen split?				}


procedure DrawTabStop (h,stop: integer); extern;

{ draw one tab stop						}
{								}
{ Parameters:							}
{    h - column number (from 0)					}
{    stop - tab stop						}


procedure Expand;

{ Expand a compacted buffer					}


procedure Find (patt: searchString; whole,caseFlag,fold,flagErrors: boolean);
extern;

{ Find and select a pattern					}
{								}
{ Parameters:							}
{    patt - pointer to the string to search for			}
{    whole - whole word search?					}
{    caseFlag - case sensitive search?				}
{    fold - fold whitespace?					}
{    flagErrors - flag an error if the string is not found?	}


function FindActiveFile (wp: grafPortPtr): boolean;

{ find the indicated window, and make it current 		}
{								}
{ Parameters:							}
{    wp - window of the file to locate				}
{								}
{ Returns: true if the file is found, else false 		}


procedure FindCursor;  extern;

{ find the cursor row and column based on its position		}


function FindCursorColumn: integer;

{ find the column that the cursor is actually in 		}
{								}
{ Returns: column that the cursor is in				}


procedure FollowCursor;

{ make sure the cursor is on the screen				}


procedure GrowBuffer;

{ expand the size of the current buffer				}


procedure Key (ch: char);

{ Enter a key in the buffer					}
{								}
{ Parameters:							}
{    ch - key to enter in the buffer				}


function LoadFile (name: gsosInStringPtr): boolean;

{ load a new file						}
{								}
{ Parameters:							}
{    name - name of the file to load				}
{								}
{ Returns: true if the load is successful			}


procedure LoadFileStateResources (name: gsosInStringPtr);

{ load the file state resource and set the variables		}
{								}
{ Parameters:							}
{    name - name of the file to load				}


function Max2 (l: longint): integer;

{ find the largest integer that is <= l				}
{								}
{ Parameters:							}
{    l - long integer						}
{								}
{ Returns: largest two-byte integer <= to l			}


procedure MoveBack (sp,dp: charPtr; size: longint); extern;

{ move size bytes from sp to dp, where sp > dp			}
{								}
{ Parameters:							}
{    sp - source pointer 					}
{    dp - destination pointer					}
{    size - # of bytes to move					}


procedure MoveCursor (col: integer; deltaRow: longint);

{ move the cursor as appropriate 				}
{								}
{ Parameters:							}
{    col - column to move the cursor to				}
{    deltaRow - change in cursor row from old value		}


procedure MoveDown (lines: integer);

{ Move the cursor toward the end of the file			}
{								}
{ Parameters:							}
{    lines - move down this many lines				}


procedure MoveForward (sp,dp: charPtr; size: longint); extern;

{ move size bytes from sp-1 to dp-1, indexing back; sp < dp	}
{								}
{ Parameters:							}
{    sp - source pointer+1					}
{    dp - destination pointer+1					}
{    size - # of bytes to move					}


procedure MoveLeft (cols: integer);

{ Move the cursor toward the start of a line			}
{								}
{ Parameters:							}
{    cols - number of columns to move				}


procedure MoveRight (cols: integer);

{ Move the cursor toward the end of a line			}
{								}
{ Parameters:							}
{    cols - number of columns to move				}


procedure MoveToStart; extern;

{ move the cursor to the start of the current line		}


procedure MoveUp (lines: integer);

{ Move the cursor toward the start of the file			}
{								}
{ Parameters:							}
{    lines - move up this many lines				}


function NewWindowFrame(xLoc,yLoc,dataW,dataH: integer; plane: grafPortPtr;
   infoBar: boolean; title: pStringPtr): grafPortPtr; extern;

{ open a new window						}
{								}
{ Parameters:							}
{    xLoc,yLoc - location of the window				}
{    dataW,dataH - size of data area				}
{    plane - window plane					}
{    infoBar - is there an information bar?			}
{    title - initial window name 				}
{								}
{ Returns: grafPort for the new window				}


procedure OpenNewWindow (x,y,w,h: integer; name: gsosInStringPtr);

{ open a window							}
{								}
{ Parameters:							}
{    x,y - location of the window				}
{    w,h - size of the window					}
{    name - name of the window					}


procedure DoPaste (useScrap: boolean; rPattPtr: searchStringPtr; len: integer);
extern;

{ paste the scrap into the current file at the cursor location	}
{								}
{ Parameters:							}
{    useScrap - use the scrap? (or use rPattPtr) 		}
{    rPattPtr - pointer to the chars to paste			}
{    len - length of the characters to paste			}


procedure Position (column,row: integer);

{ Position cursor - stays on screen!				}
{								}
{ Parameters:							}
{    column - column to place the cursor 			}
{    row - row to place the cursor				}


procedure ReplaceAll (search,replace: searchString;
  whole,caseFlag,fold: boolean);

{ Global search & replace, no checking				}
{								}
{ Parameters:							}
{    search - search string					}
{    replace - replace string					}
{    whole - whole word? 					}
{    caseFlag - case sensitive?					}
{    fold - fold whitespace?					}


procedure ResetCursor;

{ switch to the arrow cursor					}
{								}
{ Notes: Defined externally in PCommon				}
          

procedure SaveFile (paction: integer);

{ save the current file						}
{								}
{ Parameters:							}
{    paction - FastFile action to take after the save		}


procedure ScrollDown (lines: longint); extern;

{ Move toward the end of the file				}
{								}
{ Parameters:							}
{    lines - number of lines to scroll				}


procedure ScrollUp (lines: longint); extern;

{ Move toward the beginning of the file				}
{								}
{ Parameters:							}
{    lines - number of lines to scroll				}


procedure SetTabs (language: integer; var insert,autoReturn: boolean;
  var ruler: rulerType; var newDebug: boolean); extern;

{ fill in info from SYSTABS file 				}
{								}
{ Parameters:							}
{    language - language number					}
{    insert - insert flag					}
{    autoReturn - auto return falg				}
{    ruler - tab line						}
{    newDebug - use the new debug characters?			}


procedure ShiftLeft;

{ Shift the selected text left one column			}


procedure ShiftRight;

{ Shift the selected text right one column			}


procedure SplitTheScreen (v: integer; portR: rect);

{ split the screen at v						}
{								}
{ Parameters:							}
{    v - 							}
{    portR -							}


procedure SwitchSplit;

{ switch the active half of the split screen			}


procedure TabChar (left: boolean);

{ move to a new tab stop 					}
{								}
{ Parameters:							}
{    left - tab left?						}


procedure UpdateAWindow;

{ update the current window					}


procedure Undo_Delete (num: longint);

{ copies num characters, starting at the cursor, to the current }
{ undo record							}
{								}
{ Parameters:							}
{    num - number of characters to save				}


procedure Undo_Insert (num: longint);

{ notes that num characters are about to be inserted into the	}
{ file at the cursor location.					}
{								}
{ Parameters:							}
{    num - number of characters to save				}


procedure Undo_New;

{ Pushes the current undo record (if any) and creates a new one }


procedure Undo_PopAll;

{ pop all undo records from the list				}


procedure Undo_Pop;

{ pops the top undo record from the undo stack			}


procedure UpperCase (str: pStringPtr); extern;

{ convert all characters in a string to uppercase		}
{								}
{ Parameters:							}
{    str - address of the string to convert			}


procedure WordTabLeft;

{ move left to the start of the previous word			}


procedure WordTabRight;

{ move right to the start of the next word			}

{-----------------------------------------------------------------------------}

implementation

const
   buffIncrement = 4096; 		{"chunk" size of a file buffer}
 
   text		 = 0;			{scrap types}
   picture	 = 1;

   fsResType = 1;			{file state resource type}
   fsResID = 1;				{file state resource ID}

type
   convert = record
      lsw,msw: integer;
      end;

   fileStateFlags = (f_indentedReturns, f_lineSelect, f_unused,
      f_insertPRIZM, f_useTabs, f_insertEdit, f_newDebug, f_showRuler);
   fileStateRecord = record		{file state information}
      pCount: integer;			{parameter count (6)}
      version: integer;			{record version (1)}
      flags: set of fileStateFlags;	{file state information}
      cursor: longint;			{cursor position}
      select: longint;			{selection position}
      position: rect;			{window position}
      tabs: rulerType;			{tab line}
      end;
   fileStatePtr = ^fileStateRecord;

var
   cursorPort: grafPortPtr;		{grafPort where the cursor is flashing}
   doingUndo: boolean;			{is an undo in progress?}

{-- External subroutines -----------------------------------------------------}

procedure Check255; extern;

{ make sure the current line is < 256 chars long 		}


procedure CheckMenuItems; extern;

{ check and uncheck file dependent menu items			}


procedure DoShowRuler; extern;

{ show or hide the ruler 					}
{								}
{ Notes: Declared externally in Buffer.pas			}


procedure DrawOneLine (line: integer); extern;

{ draw one line on a non-split screen				}
{								}
{ Parameters:							}
{    line - line number of line to draw				}


function InsertChar: boolean; extern;

{ insert a character in the buffer				}
{								}
{ Returns: true if the insert was successful			}


function ScanForward (sp: charPtr; lines: longint): charPtr; extern;

{ starting at sp, move forward lines lines			}
{								}
{ Parameters:							}
{    sp - starting pointer					}
{    lines - number of lines to move				}
{								}
{ Returns: pointer to start of new line				}


procedure TrackCursor (v,h,width,height: integer; redraw: boolean); extern;

{ change the cursor based on screen position			}
{								}
{ Parameters:							}
{    v,h -							}
{    width,height -						}
{    redraw -							}

{-----------------------------------------------------------------------------}

procedure FixPosition;

{ reset the file's pointers after the buffer has moved          }

var
   disp: longint;			{movement of the file buffer}
   lBuffStart: charPtr;			{local copy of buffStart}

begin {FixPosition}
with currentFile do begin
   lBuffStart := buffHandle^;		{compute position shift}
   disp := ord4(lBuffStart)-ord4(buffStart);
   buffStart := lBuffStart;		{update pointers}
   buffEnd := pointer(ord4(buffStart)+buffSize);
   gapStart := pointer(ord4(gapStart)+disp);
   pageStart := pointer(ord4(pageStart)+disp);
   cursor := pointer(ord4(cursor)+disp);
   select := pointer(ord4(select)+disp);
   end; {with}
end; {FixPosition}


function Max2 {l: longint): integer};

{ find the largest integer that is <= l				}
{								}
{ Parameters:							}
{    l - long integer						}
{								}
{ Returns: largest two-byte integer <= to l			}

begin {Max2}
if l > maxint then
   max2 := maxint
else
   max2 := convert(l).lsw;
end; {Max2}


procedure MoveCursor {col: integer; deltaRow: longint};

{ move the cursor as appropriate 				}
{								}
{ Parameters:							}
{    col - column to move the cursor to				}
{    deltaRow - change in cursor row from old value		}

label 1;

var
   autoGo, breakPoint: 0..255;		{values used in this file}

begin {MoveCursor}
currentFile.verticalMove := false;
with currentFile do begin

   {decide which characters are in use}
   if newDebug then begin
      autoGo := newAutoGo;
      breakPoint := newBreakPoint;
      end {if}
   else begin
      autoGo := oldAutoGo;
      breakPoint := newBreakPoint;
      end; {else}

   {cursor moves invalitate any selection}
   if selection then begin
      selection := false;
      DrawScreen;
      end; {if}

   {move to the start of the current line}
   MoveToStart;
   if deltaRow < 0 then
      while deltaRow <> 0 do begin
	 if cursor = buffStart then goto 1;
	 if cursor = pageStart then begin
	    if gapStart = buffStart then goto 1;
	    cursor := pointer(ord4(gapStart)-1);
	    end {if}
	 else
	    cursor := pointer(ord4(cursor)-1);
	 MoveToStart;
	 deltaRow := deltaRow+1;
	 end {while}
   else

      {move forward deltaRow rows}
      while deltaRow <> 0 do begin
	 if cursor = buffEnd then begin
	    cursor := pointer(ord4(cursor)-1);
	    MoveToStart;
	    goto 1;
	    end; {if}
	 while cursor^ <> return do
	    cursor := pointer(ord4(cursor)+1);
	 cursor := pointer(ord4(cursor)+1);
	 if cursor = gapStart then
	    cursor := pageStart;
	 deltaRow := deltaRow-1;
	 end; {while}
   1:
   {move forward to the correct column}
   if (ord(cursor^) = breakPoint) or (ord(cursor^) = autoGo) then
      cursor := pointer(ord4(cursor) + 1);
   if col < 0 then col := 0;
   cursorColumn := 0;
   while col <> 0 do begin
      cursorColumn := cursorColumn+1;
      col := col-1;
      if cursor^ <> return then begin
         if cursor^ = tab then begin
            while ruler[cursorColumn] = 0 do begin
               cursorColumn := cursorColumn+1;
               col := col-1;
               end; {while}
            if col < 0 then col := 0;
            end; {if}
         cursor := pointer(ord4(cursor)+1);
         end; {if}
      end; {while}
   end; {with}
end; {MoveCursor}


function FindCursorColumn{: integer};

{ find the column that the cursor is actually in 		}
{								}
{ Returns: column that the cursor is in				}

var
   autoGo, breakPoint: 0..255;		{values used in this file}
   ccol: integer;			{cursor column}
   lCursor: charPtr;			{local work copy of cursor}

begin {FindCursorColumn}
currentFile.verticalMove := false;
with currentFile do begin

   {decide which characters are in use}
   if newDebug then begin
      autoGo := newAutoGo;
      breakPoint := newBreakPoint;
      end {if}
   else begin
      autoGo := oldAutoGo;
      breakPoint := newBreakPoint;
      end; {else}

   lCursor := cursor;
   MoveToStart;
   if (ord(cursor^) = breakPoint) or (ord(cursor^) = autoGo) then
      cursor := pointer(ord4(cursor) + 1);
   ccol := 0;
   if ord4(lCursor) > ord4(cursor) then
      while lCursor <> cursor do begin
         if cursor^ = tab then
            repeat
               ccol := ccol+1
            until (ccol > 255) or (ruler[ccol] <> 0)
         else
            ccol := ccol+1;
         cursor := pointer(ord4(cursor) + 1);
         end; {while}
   FindCursorColumn := ccol;
   cursor := lCursor;
   end; {with}
end; {FindCursorColumn}


procedure DeleteACharacter;

{ delete the character to the left of the cursor 		}

var
   cp: charPtr;				{work character pointer}

begin {DeleteACharacter}
currentFile.verticalMove := false;
with currentFile do begin
   cp := cursor;
   cursor := pointer(ord4(cursor)-1);
   Undo_Delete(1);
   MoveForward(cursor,cp,ord4(cp)-ord4(pageStart));
   cursor := cp;
   pageStart := pointer(ord4(pageStart)+1);
   cursorColumn := FindCursorColumn;
   changed := true;
   changesSinceCompile := true;
   end; {with}
end; {DeleteACharacter}


procedure CheckForBlanks;

{ check for, and remove, trailing blanks 			}

var
   cp: charPtr;				{work pointer}

begin {CheckForBlanks}
with currentFile do
   if (cursor <> pageStart) and (cursor^ = return) then begin
      cp := pointer(ord4(cursor)-1);
      while (cp^ = space) and (cursor <> pageStart) do begin
	 DeleteACharacter;
	 cp := pointer(ord4(cursor)-1);
	 cursorColumn := cursorColumn+1;
	 end; {while}
      end; {if}
end; {CheckForBlanks}


procedure BlankExtend;

{ if the cursor is past the end of line, insert spaces		}

var
   cc: integer;				{cursor column}
   cp,cpn: charPtr;			{work pointers}
   length: longint;			{size of memory to move}

begin {BlankExtend}
with currentFile do begin
   cc := FindCursorColumn;		{if cursor is past EOL, blank fill}
   if cc <> cursorColumn then begin
      cc := cursorColumn-cc;		{cc := # blanks to insert}
      Undo_Insert(cc);			{note the insertion of characters}
					{if needed, grow the buffer}
      if ord4(gapStart)+cc >= ord4(pageStart) then
	 GrowBuffer;
      if ord4(gapStart)+cc < ord4(pageStart) then begin
					{make room in the file}
	 length := ord4(cursor)-ord4(pageStart);
	 MoveBack(pageStart,pointer(ord4(pageStart)-cc),length);
	 pageStart := pointer(ord4(pageStart)-cc);
	 cp := pointer(ord4(cursor)-cc); {blank fill the new area}
	 while cp <> cursor do begin
	    cp^ := ord(' ');
	    cp := pointer(ord4(cp)+1);
	    end; {while}
	 end; {if gapStart+cc < pageStart}
      end; {if cc <> cursorColumn}
   end; {with}
end; {BlankExtend}

{-----------------------------------------------------------------------------}

procedure Blink;

{ blink the cursor						}

label 1;

var
   cf: buffPtr;				{current window's buffer pointer}
   didIt: boolean;			{did we actually draw it?}
   done: boolean;			{for loop termination test}
   fw: grafPortPtr;			{for seeing who's on top}
   port: grafPortPtr;			{caller's grafPort}
   x,y: integer; 			{for calculating cursor position}


   function IsWindow (ptr: grafPortPtr): boolean;

   { See if a pointer is a valid window				}
   {								}
   { Parameters: 						}
   {	ptr - pointer to check					}
   {								}
   { Returns: true if ptr is a window, else false		}

   var
      wp: grafPortPtr;			{current window}

   begin {IsWindow}
   IsWindow := false;
   wp := GetFirstWindow;
   while wp <> nil do
      if wp = ptr then begin
	 wp := nil;
	 IsWindow := true;
	 end {if}
      else
	 wp := GetNextWindow(wp);
   end; {IsWindow}


begin {Blink}
if cursorVisible then
   fw := cursorPort
else
   fw := FrontWindow;
if not IsWindow(fw) then begin
   cursorVisible := false;
   goto 1;
   end; {if}
port := GetPort;
SetPort(fw);
SetSolidPenPat(whitePen);
SetPenMode(2);
if fw = currentFile.wPtr then
   cf := @currentFile
else begin
   cf := filePtr;
   done := false;
   repeat
      if cf = nil then
	 done := true
      else if cf^.wPtr = fw then
	 done := true
      else
	 cf := cf^.next;
   until done;
   end; {else}
if cf <> nil then begin
   with cf^ do
      if (leftColumn <= cursorColumn)
	 and (cursorColumn < width+leftColumn)
	 and (cursorRow >= 0)
	 and (cursorRow < height)
	 and not selection then begin
	 x := (cursorColumn-leftColumn+1)*chWidth-1;
	 y := (convert(cursorRow).lsw+1)*chHeight+dispFromTop;
	 MoveTo(x,y);
	 if insert then
	    LineTo(x,y-chHeight+1)
	 else
	    LineTo(x+chWidth,y);
	 end; {if}
   cursorVisible := not cursorVisible;
   if cursorVisible then
      cursorPort := port;
   end; {if}
SetPort(port);
1:
lastHeartBeat := TickCount;
end; {Blink}


procedure ChangeSize {h,v: integer; update: boolean};

{ change the size of the current window				}
{								}
{ Parameters:							}
{    h,v - new size						}
{    update -							}

const
   minHeight	 = 46;			{min window height in pix.}
   minWidth	 = 106;			{min window width, in pix.}

var
   r: rect;				{for creating controls}
   resize: boolean;			{resize even on update?}
   fHeight: integer;			{height of free area}

begin {ChangeSize}
resize := not update;			{set default resize flag}
if h < minWidth then begin		{don't go below min size}
   h := minWidth;
   resize := true;
   end; {if}
if v < minHeight then begin
   v := minHeight;
   resize := true;
   end; {if}
r.h1 := 0; r.h2 := h;			{set up the rectangle}
r.v1 := 0; r.v2 := v;
with currentFile do begin		{size and draw the controls}
   if resize then begin
      SizeWindow(h,v,wPtr);		{change the window's size}
      EraseRect(r);
      end; {if}
   width := r.h2 div 8 - 4;		{set the width}
   maxHeight := r.v2-hScrollHeight;
   if splitScreen then begin		{redo a split screen}
      fHeight := v-(5*chHeight+hScrollHeight);
      if dispFromTop = 0 then
	 heightAlt := (v-dispFromTopAlt-2-hScrollHeight) div chHeight
      else
	 height := (v-dispFromTop-2-hScrollHeight) div chHeight;
      if (dispFromTop > fHeight) or (dispFromTopAlt > fHeight) then
	 SplitTheScreen(0,r)
      else if dispFromTop = 0 then
	 SplitTheScreen(height*chHeight,r)
      else
	 SplitTheScreen(heightAlt*chHeight,r);
      end {if}
   else begin				{redo a non-split screen}
      height := (r.v2-hScrollHeight) div 8; {set screen height}
      if vScroll <> nil then begin	{dump old controls, if any}
	 DisposeControl(vScroll);
	 DisposeControl(hScroll);
	 DisposeControl(grow);
	 end; {if}
      CreateControls(@r);		{create & draw new controls}
      DrawControls(wPtr);
      end; {else}
   if resize then			{redraw the screen if we cleared it}
      DrawScreen;
   if showRuler and not update then begin {redraw the ruler}
      currentPtr^ := currentFile;
      StartInfoDrawing(r,wPtr);
      DrawRuler(r,ord4(@currentFile),wPtr);
      EndInfoDrawing;
      end; {if}
   end; {with}
end; {ChangeSize}


procedure Compact;

{ Compact an expanded buffer					}

var
   length: longint;			{length of the end text region}

begin {Compact}
with currentFile do
   if expanded then begin
      expanded := false;
					{move the buffer back}
      length := ord4(buffEnd)-ord4(pageStart);
      MoveBack(pageStart,gapStart,length);
					{repair cursor and select, if needed}
      if ord4(cursor) >= ord4(pageStart) then
	 cursor := pointer(ord4(cursor)+ord4(gapStart)-ord4(pageStart));
      if ord4(select) >= ord4(pageStart) then
	 select := pointer(ord4(select)+ord4(gapStart)-ord4(pageStart));
      pageStart := gapStart;		{fix gapStart, pageStart}
      gapStart := pointer(ord4(gapStart)+length);
      if not compiling then		{let the file float}
	 HUnLock(buffHandle);
      end; {if}
end; {Compact}


procedure CopySelection;

{ copy selected text to the scrap				}

var
   p1,p2: charPtr;			{character pointer}

begin {CopySelection}
with currentFile do
   if selection then begin
      ZeroScrap; 			{get ready for the scrap}
      Compact;				{make the buffer contiguous}
      if ord4(cursor) < ord4(select) then {sort the pointers}
	 begin
	 p1 := cursor;
	 p2 := select;
	 end {if}
      else begin
	 p1 := select;
	 p2 := cursor;
	 end; {else}
      PutScrap(ord4(p2)-ord4(p1),text,p1); {write the scrap}
      Expand;				{re-expand the buffer}
      end; {if}
end; {CopySelection}


procedure CreateControls {portRect: rectPtr};

{ create a set of controls for a window with the given size	}
{								}
{ Parameters:							}
{    portRect - size of the window				}

var
   r: rect;				{for building controls}

begin {CreateControls}
with currentFile do begin
   r.h1 := portRect^.h2-(vScrollWidth-2); {create a grow box}
   r.h2 := portRect^.h2+2;
   r.v1 := portRect^.v2-(hScrollHeight-1);
   r.v2 := portRect^.v2+1;
   grow := NewControl(wPtr,r,nil,0,0,0,0,pointer($08000000),0,nil);
   r.h1 := -2;				{create horizontal scroll bar}
   r.h2 := portRect^.h2-(vScrollWidth-4);
   r.v1 := portRect^.v2-(hScrollHeight-1);
   r.v2 := portRect^.v2+1;
   hScroll := NewControl(wPtr,r,nil,$1C,leftColumn,
      width,256,pointer($06000000),0,nil);
   r.h2 := portRect^.h2+2;		{create vertical scroll bar}
   r.h1 := portRect^.h2-(vScrollWidth-2);
   r.v1 := 0;
   if splitScreen then
      r.v2 := dispFromTopAlt-3
   else begin
      r.v2 := portRect^.v2-(hScrollHeight-2);
      if r.v2 >= 10*chHeight+hScrollHeight+1 then
	 r.v1 := 4;
     end; {else}
   vScroll := NewControl(wPtr,r,nil,3,max2(topLine),height,
      max2(numLines+height),pointer($06000000),0,nil);
   splitScreenRect := r; 		{create split screen control}
   with splitScreenRect do begin
      if splitScreen then begin
	 v1 := dispFromTopAlt-3;
	 v2 := dispFromTopAlt+1;
	 end {if}
      else begin
	 v2 := r.v1;
	 v1 := 0;
	 end; {else}
      end; {with}
   SetPenMode(0);
   DrawSplitScreenControl(splitScreenRect,splitScreen);
   if splitScreen then begin		{create vert. scroll bar for alt screen}
      r.v1 := dispFromTopAlt+1;
      r.v2 := portRect^.v2-(hScrollHeight-2);
      vScrollAlt := NewControl(wPtr,r,nil,3,max2(topLineAlt),heightAlt,
	 max2(numLines+heightAlt),pointer($06000000),0,nil);
      end; {if}
   end; {with}
end; {CreateControls}


procedure DeleteSelection;

{ remove selected text from the file				}

label 1;

var
   cp,temp: charPtr;			{temp char pointers}
   oldNumLines: longint; 		{original value for numLines}

begin {DeleteSelection}
with currentFile do
   if selection then begin
      if ord4(cursor) > ord4(select) then begin
	 temp := cursor; 		{make sure cursor is before select}
	 cursor := select;
	 select := temp;
	 FindCursor;			{recalculate the cursor variables}
	 end; {if}
      FollowCursor;			{get cursor on the screen}
      if select = buffEnd then begin	{never delete the CR at EOF!}
	 select := pointer(ord4(select)-1);
	 if select = cursor then begin
	    selection := false;
	    Key(char(deleteCh));
	    goto 1;
	    end; {if}
	 end; {if}
      Undo_New;				{keep the characters for possible undo}
      Undo_Delete(ord4(select)-ord4(cursor));
      oldNumLines := numLines;		{recompute numLines}
      cp := cursor;
      while cp <> select do begin
	 if cp^ = return then
	    numLines := numLines-1;
	 cp := pointer(ord4(cp)+1);
	 end; {while}
      if cursor = pageStart then 	{remove the selected text}
	 pageStart := select
      else begin
	 MoveForward(cursor,select,ord4(cursor)-ord4(pageStart));
	 pageStart := pointer(ord4(pageStart)+ord4(select)-ord4(cursor));
	 end; {if}
      cursor := select;			{reposition the cursor}
      FindCursor;			{recompute cursor position}
      if splitScreen then		{adjust alt topLine}
	 if topLineAlt > topLine+cursorRow then begin
	    topLineAlt := topLineAlt-(oldNumLines-numLines);
	    if topLineAlt < topLine+cursorRow then
	       topLineAlt := topLine+cursorRow;
	    end; {if}
      selection := false;		{selection is gone...}
      CheckForBlanks;			{check for trailing blanks}
      changed := true;			{the file has changed}
      changesSinceCompile := true;
      DrawScreen;			{redraw the screen}
      if splitScreen then begin		{reset the controls size}
	 SetCtlParams(max2(numLines+heightAlt),heightAlt,vScrollAlt);
	 SetCtlValue(max2(topLineAlt),vScrollAlt);
	 end; {if}
      SetCtlParams(max2(numLines+height),height,vScroll);
      SetCtlValue(max2(topLine),vScroll);
      end; {if}
1:
end; {DeleteSelection}


procedure DoDeleteToEOL;

{ delete from the cursor to the end of the line			}

begin {DoDeleteToEol}
currentFile.verticalMove := false;
with currentFile do begin
   DeleteSelection;
   select := cursor;
   while select^ <> return do
      select := pointer(ord4(select)+1);
   selection := true;
   Key(chr(deleteCh));
   DrawLine(convert(currentFile.cursorRow).lsw)
   end; {with}
end; {DoDeleteToEol}


procedure DoSetClearMark {ch: integer};

{ set or clear auto go or break point status from a block of	}
{ text								}
{								}
{ Parameters:							}
{    ch - character to set					}

var
   cp1: charPtr; 			{work character pointer}
   lCursor: charPtr;			{temp copy of cursor}
   setPoint: boolean;			{set auto go (or clear)?}


   procedure DoSetClear (setPoint: boolean; ch: integer);

   { set or clear a break point or auto-go mark			}
   {								}
   { Parameters: 						}
   {	setPoint - set the character? (or clear it)		}
   {	ch - character to set (unused for clear)		}

   var
      autoGo, breakPoint: 0..255;	{values used in this file}
      cp: charPtr;			{work pointer}

   begin {DoSetClear}
   with currentFile do begin
      if newDebug then begin		{decide which characters are in use}
         autoGo := newAutoGo;
         breakPoint := newBreakPoint;
         end {if}
      else begin
         autoGo := oldAutoGo;
         breakPoint := newBreakPoint;
         end; {else}
      if setPoint then begin		{if an old mark exists, replace it}
	 if cursor^ in [autoGo,breakPoint] then
	    cursor^ := ch
	 else begin
	    if InsertChar then begin	{no old mark - insert a new one}
	      cp := pointer(ord4(cursor)-1);
	      cp^ := ch;
	      if ord4(lCursor) <= ord4(cursor) then
		 lCursor := pointer(ord4(lCursor)-1);
	      end; {if}
	    end; {else}
	 end {if}
      else if cursor^ in [autoGo,breakPoint] then begin
	 cursor := pointer(ord4(cursor)+1); {delete any old mark}
	 cursorColumn := cursorColumn+1;
	 DeleteACharacter;
	 if ord4(lCursor) <= ord4(cursor) then
	    lCursor := pointer(ord4(lCursor)+1);
	 end; {else}
      end; {with}
   end; {DoSetClear}


begin {DoSetClearMark}
with currentFile do begin
   FollowCursor;
   if not selection then
      select := cursor;
   if ord4(cursor) > ord4(select) then begin
      cp1 := cursor;
      cursor := select;
      select := cp1;
      FindCursor;
      end; {if}
   lCursor := cursor;
   MoveToStart;
   setPoint := cursor^ <> ch;
   DoSetClear(setPoint,ch);
   cp1 := cursor;
   cursor := pointer(ord4(cursor)+1);
   while ord4(cursor) < ord4(select) do begin
      if cp1^ = return then
	 DoSetClear(setPoint,ch);
      cp1 := cursor;
      cursor := pointer(ord4(cursor)+1);
      end; {while}
   cursor := lCursor;
   FindCursor;
   DrawScreen;
   end; {with}
end; {DoSetClearMark}


procedure DoUndo;

{ undo the last change						}

var
   disp: longint;			{for pasting..}
   gap: longint; 			{size of gap in buffer}
   ub: undoPtr;				{work pointer}

begin {DoUndo}
currentFile.verticalMove := false;
ub := currentFile.undoList;
if ub <> nil then begin
   doingUndo := true;			{let everyone know what we're doing}
   with ub^,currentFile do begin
      if insertChars <> 0 then begin	{remove newly typed characters}
	 select := pointer(ord4(buffStart)+insertPos);
	 cursor := pointer(ord4(select)-insertChars);
	 gap := ord4(pageStart)-ord4(gapStart);
	 if ord4(select) >= ord4(gapStart) then
	    select := pointer(ord4(select)+gap);
	 if ord4(cursor) >= ord4(gapStart) then
	    cursor := pointer(ord4(cursor)+gap);
	 FindCursor;
	 selection := true;
	 DeleteSelection;
	 if cursor^ = RETURN then
	    cursorColumn := insertCol;
	 end; {if}
      if deleteChars <> 0 then begin	{insert deleted characters}
	 cursor := pointer(ord4(buffStart)+deletePos);
	 if ord4(cursor) >= ord4(gapStart) then
	    cursor := pointer(ord4(cursor)+ord4(pageStart)-ord4(gapStart));
	 FindCursor;
	 disp := ord4(deleteHandle^);
	 while deleteChars > maxint do begin
	    DoPaste(false,pointer(disp),maxint);
	    disp := disp+maxint;
	    deleteChars := deleteChars-maxint;
	    end; {while}
	 DoPaste(false,pointer(disp),convert(deleteChars).lsw);
	 end; {if}
      end; {with}
   doingUndo := false;			 {done}
   Undo_Pop;				 {pop the top record from the stack}
   end; {if}
end; {DoUndo}


procedure DrawLine {line: integer};

{ draw one line on the screen					}
{								}
{ Parameters:							}
{    line - line to draw 					}

begin {DrawLine}
with currentFile do
   if splitScreen and (topLineAlt <= topLine+cursorRow)
      and (topLineAlt+heightAlt >= topLine+cursorRow) then
      DrawScreen
   else
      DrawOneLine(line);
end; {DrawLine}


procedure DrawScreen;

{ redraw the entire screen					}

var
   delta: longint;			{distance to scroll}

begin {DrawScreen}
if not disableScreenUpdates then
   with currentFile do begin
      DrawOneScreen(width,height,dispFromTop,leftColumn,pageStart,buffEnd,
         wPtr,ruler);
      if splitScreen then begin
	 if topLine > topLineAlt then begin
	    if topLine-topLineAlt < heightAlt then begin
	       disableScreenUpdates := true; {draw a screen split by the main screen}
	       delta := topLine-topLineAlt;
	       ScrollUp(delta);
	       disableScreenUpdates := false;
	       DrawOneScreen(width,heightAlt,dispFromTopAlt,leftColumn,pageStart,
		  buffEnd,wPtr,ruler);
	       disableScreenUpdates := true;
	       ScrollDown(delta);
	       disableScreenUpdates := false;
	       end {if}
	    else 			{draw a screen before the buffer split}
	       DrawOneScreen(width,heightAlt,dispFromTopAlt,leftColumn,
		  ScanForward(buffStart,topLineAlt),gapStart,wPtr,ruler);
	    end {if}
	 else				{draw a screen after the buffer split}
	    DrawOneScreen(width,heightAlt,dispFromTopAlt,leftColumn,
	       ScanForward(pageStart,topLineAlt-topLine),buffEnd,wPtr,ruler);
	 end; {if}
      if executing then
         if sourcePtr <> nil then
	    if sourcePtr = currentPtr then
	       if status in [step,trace] then
		  if ord(cursorRow) < height then
		     DrawMark(stepChar, ord(cursorRow), dispFromTop);
      end; {with}
end; {DrawScreen}


procedure DrawSplitScreenControl {r: rect; splitScreen: boolean};

{ draw the split screen control					}
{								}
{ Parameters:							}
{    r - split screen control location				}
{    splitScreen - is the screen split?				}

begin {DrawSplitScreenControl}
if r.v2 > r.v1 then begin
   SetSolidPenPat(blackPen);
   PaintRect(r);
   if splitScreen then begin
      SetSolidPenPat(purplePen);
      MoveTo(0,r.v1+2);
      LineTo(r.h1-1,r.v1+2);
      SetSolidPenPat(whitePen);
      MoveTo(0,r.v1+1);
      LineTo(r.h1-1,r.v1+1);
      MoveTo(0,r.v1+3);
      LineTo(r.h1-1,r.v1+3);
      end; {if}
   end; {if}
end; {DrawSplitScreenControl}


procedure Expand;

{ Expand a compacted buffer					}

var
   size: longint;			{size of gap}

begin {Expand}
with currentFile do
   if not expanded then begin
      expanded := true;
      HLock(buffHandle); 		{lock the file}
      if buffHandle^ <> buffStart then
	 FixPosition;
					{move the buffer forward}
      MoveForward(gapStart,buffEnd,ord4(gapStart)-ord4(pageStart));
      size := ord4(buffEnd)-ord4(gapStart);
					{if needed, adjust cursor and select}
      if ord4(cursor) >= ord4(pageStart) then
	 cursor := pointer(ord4(cursor)+size);
      if ord4(select) >= ord4(pageStart) then
	 select := pointer(ord4(select)+size);
      gapStart := pageStart;		{fix gapStart, pageStart}
      pageStart := pointer(ord4(pageStart)+size);
      end; {if}
end; {Expand}


function FindActiveFile {wp: grafPortPtr): boolean};

{ find the indicated window, and make it current 		}
{								}
{ Parameters:							}
{    wp - window of the file to locate				}
{								}
{ Returns: true if the file is found, else false 		}

label 1;

var
   lPtr: buffPtr;			{for walking file list}

begin {FindActiveFile}
FindActiveFile := true;
if (currentPtr = nil) or (wp <> currentFile.wPtr) then begin
   FindActiveFile := false;
   lPtr := filePtr;			{find the correct file}
   if lPtr <> nil then begin
      while lPtr^.wPtr <> wp do begin
	 lPtr := lPtr^.next;
	 if lPtr = nil then
	    goto 1;
	 end; {while}
      if currentPtr <> nil then begin
	 Compact;			{compact the current file}
	 if not compiling then		{let the file float}
	    HUnLock(currentFile.buffHandle);
	 currentPtr^ := currentFile;	{archive the current file's info}
	 end;
      currentPtr := lPtr;
      currentFile := currentPtr^;
      FindActiveFile := true;
      end; {if}
   end; {if}
1:
if currentPtr <> nil then
   Expand;
end; {FindActiveFile}


procedure FollowCursor;

{ make sure the cursor is on the screen				}

var
   change: boolean;			{does the screen need repainting?}
   r: rect;				{info rect}
   temp: longint;			{temp variable}
   updateHThumb: boolean;		{does the horiz. thumb need updating?}

begin {FollowCursor}
change := false;
updateHThumb := false;
with currentFile do begin
   if cursorColumn < leftColumn then begin
      leftColumn := cursorColumn;
      change := true;
      updateHThumb := true;
      end {if}
   else if cursorColumn >= leftColumn+width then begin
      leftColumn := cursorColumn-width+1;
      change := true;
      updateHThumb := true;
      end; {else}
   if cursorRow < 0 then begin
      ScrollUp(-cursorRow);
      change := false;
      end {if}
   else if cursorRow >= height then begin
      ScrollDown(cursorRow-(height-1));
      change := false;
      end; {else}
   if not disableScreenUpdates then begin
      if change then begin
	 DrawScreen;
	 if showRuler then begin
	    currentPtr^ := currentFile;
	    StartInfoDrawing(r,wPtr);
	    DrawRuler(r,ord4(@currentFile),wPtr);
	    EndInfoDrawing;
	    end; {if}
	 end; {if}
      if updateHThumb then
	 SetCtlValue(leftColumn,hScroll);
      end; {if}
   end; {with}
end; {FollowCursor}


procedure GrowBuffer;

{ expand the size of the current buffer				}

begin {GrowBuffer}
with currentFile do begin
   Compact;				{compact the buffer}
   HUnLock(buffHandle);			{grow the buffer}
   SetHandleSize(buffSize+buffIncrement,buffHandle);
   if ToolError = 0 then begin
      HLock(buffHandle);
      buffSize := buffSize+buffIncrement; {update size}
      FixPosition;
      end {if}
   else
      OutOfMemory;
   Expand;
   end; {with}
end; {GrowBuffer}


procedure Key {ch: char};

{ Enter a key in the buffer					}
{								}
{ Parameters:							}
{    ch - key to enter in the buffer				}

label 1;

var
   cp: charPtr;				{work character pointers}
   i: integer;				{loop counter}


   function FindIndent: integer;

   { find the # cols to indent based on previous lines		}
   {								}
   { Returns: number of columns					}

   var
      cc: integer;			{cursor column}
      lCursor: charPtr;			{local cursor}
      min: charPtr;			{min allowed value for cursor}

   begin {FindIndent}
   with currentFile do begin
      lCursor := cursor;
      MoveCursor(0,-1);
      if gapStart = buffStart then
	 min := pageStart
      else
	 min := buffStart;
      while (cursor <> min) and (cursor^ = return) do
	 MoveCursor(0,-1);
      cc := 0;
      while cursor^ in [space,tab] do begin
         if cursor^ = space then begin
	    cc := cc+1;
	    cursor := pointer(ord4(cursor)+1);
            end {if}
         else begin
            repeat
	       cc := cc+1;
            until (ruler[cc] <> 0) or (cc > 255);
	    cursor := pointer(ord4(cursor)+1);
            end; {else}
	 end; {while}
      cursor := lCursor;
      FindIndent := cc;
      end; {with}
   end; {FindIndent}


   procedure TabRight (cc: integer);

   { tab and space right to column cc				}
   {								}
   { Parameters:						}
   {    cc - number of columns to skip				}

   var
      tcc: 0..256;			{column counter}
      tcount: 0..256;			{spaces to next tab stop}

   begin {TabRight}
   with currentFile do begin
      tcc := 0;
      while cc > 0 do begin
         tcount := 0;
         repeat
            tcc := tcc + 1;
            tcount := tcount + 1;
         until (ruler[tcc] <> 0) or (tcc > 255);
         if tcount <= cc then begin
            TabChar(false);
            cc := cc - tcount;
            end {if}
         else begin
            MoveRight(cc);
            cc := 0;
            end; {else}
         end; {while}
      end; {with}
   end; {TabRight}


begin {Key}
currentFile.verticalMove := false;
FollowCursor;				{get cursor on the screen}
ObscureCursor;				{hide the cursor 'til the mouse moves}
with currentFile do begin
   {--- RETURN Key ---}
   if ch = chr(return) then begin
      DeleteSelection;			{remove selected text}
					{insert mode return}
      if insert or (topLine+cursorRow+1 = numLines) then begin
	 if not insert then begin
	    cursor := pointer(ord4(buffEnd)-1);
	    cursorColumn := FindCursorColumn;
	    end; {if}
	 if (cursor <> pageStart) and (cursorColumn > 0) then begin
	    cp := pointer(ord4(cursor)-1);
	    while (cp^ = space) and (cursorColumn > 0) do begin
	       DeleteACharacter;
	       cp := pointer(ord4(cursor)-1);
	       end; {while}
	    end; {if}
	 if InsertChar then begin
	    cp := pointer(ord4(cursor)-1);
	    cp^ := return;
	    numLines := numLines+1;
	    SetCtlParams(max2(numLines+height),height,vScroll);
	    if splitScreen then begin
	       SetCtlParams(max2(numLines+heightAlt),heightAlt,vScrollAlt);
	       if topLine+cursorRow <= topLineAlt then
		  topLineAlt := topLineAlt+1;
	       end; {if}
	    cursorRow := cursorRow+1;
	    cursorColumn := 0;
	    if autoReturn then
	       if cursor^ = return then
		  TabRight(FindIndent)
	       else
		  for i := 1 to FindIndent do
		     if InsertChar then begin
			cp := pointer(ord4(cursor)-1);
			cp^ := space;
			cursorColumn := cursorColumn+1;
			end; {if}
	    end; {if InsertChar}
	 end {if insert}
      else begin 			{overstrike mode return}
	 MoveDown(1);			{move to start of next line}
	 MoveLeft(255);
	 if autoReturn then begin	{handle auto return mode}
	    if cursor^ = return then
	       TabRight(FindIndent)
	    else begin
	       while cursor^ in [space,tab] do
		  MoveRight(1);
	       end; {else}
	    end; {if}
	 end; {else}
      end {if ch = return}
   {--- DELETE Key ---}
   else if ch = chr(deleteCH) then begin
      if selection then
	 DeleteSelection 		{remove selected text}
      else begin
	 if cursorColumn = 0 then begin
	    if cursor = pageStart then
	       ScrollUp(1);
	    if cursor <> pageStart then begin
	       if splitScreen then	{adjust alternate topLine}
		  begin
		  if topLine+cursorRow <= topLineAlt then
		     topLineAlt := topLineAlt-1;
		  SetCtlParams(max2(numLines+heightAlt),heightAlt,vScrollAlt);
		  end; {if}
	       DeleteACharacter; 	{delete a line feed}
	       numLines := numLines-1;
	       cursorRow := cursorRow-1;
	       SetCtlParams(max2(numLines+height),height,vScroll);
	       cursorColumn := FindCursorColumn;
	       Check255;
	       end; {if}
	    end {if}
	 else begin
	    if FindCursorColumn < cursorColumn then
					{move the cursor back one char}
	       cursorColumn := FindCursorColumn
	    else begin
	       DeleteACharacter; 	{delete a character}
	       CheckForBlanks;		{delete trailing spaces}
	       end; {else}
	    end; {else}
	 end; {else}
      end {else if ch = deleteCH}
   {--- Printing Character ---}
   else begin				{handle a printing character}
      DeleteSelection;			{remove selected text}
      if cursor^ = return then		{don't put spaces at EOL}
	 if ch = ' ' then begin
	    MoveRight(1);
	    goto 1;
	    end; {if}
      if (not insert) and (cursor^ <> return) then begin
	 {handle an overstrike}
	 cursor^ := ord(ch);
	 MoveRight(1);
	 end {if}
      else begin
	 {insert a character}
	 BlankExtend;			{if needed, add spaces to EOL}
	 if InsertChar then begin	{insert a space in the buffer}
	    cp := pointer(ord4(cursor)-1); {place the char in the buffer}
	    cp^ := ord(ch);
	    cursorColumn := cursorColumn+1; {advance the cursor}
	    Check255;			{clip lines that are too long}
	    end; {if}
	 end; {else insert a character}
      end; {else handle printing char}
   changed := true;			{the file has changed}
   changesSinceCompile := true;
   end; {with}
1:
FollowCursor;				{make sure the cursor is visible}
end; {Key}


function LoadFile {name: gsosInStringPtr): boolean};

{ load a new file						}
{								}
{ Parameters:							}
{    name - name of the file to load				}
{								}
{ Returns: true if the load is successful			}

label 1;

var
   cp: charPtr;				{work pointer}
   ffDCB: fastFileDCBGS;		{DCB for file load}
   isFile: boolean;			{is there an existing file?}
   size: longint;			{size of the file}
   sPtr: pStringPtr;			{pointer to 'Untitled'}

begin {LoadFile}
WaitCursor;
LoadFile := true;			{no error (yet)}
with currentFile do begin
   sPtr := GetPString(104+base);	{is there an existing file?}
   isFile := not OSStringsEqual(name, PStringToOSString(sPtr));
   FreePString(104+base);
   if not isFile then begin
      buffSize := buffIncrement; 	{create a new file}
      buffHandle := pointer(NewHandle(buffSize,UserID,0,nil));
      HLock(pointer(buffHandle));
      if ToolError <> 0 then begin
	 OutOfMemory;
	 LoadFile := false;
	 goto 1;
	 end; {if}
      size := 1;
      numLines := 1;
      buffHandle^^ := return;
      end {if}
   else begin
      ffDCB.pcount := 14;		{load the file}
      ffDCB.action := 0;
      ffDCB.flags := $C000;
      ffDCB.pathName := name;
      FastFileGS(ffDCB);
      if ToolError <> 0 then begin
	 FlagError(8, ToolError);
	 LoadFile := false;
	 goto 1;
	 end; {if}
      if ffDCB.fileType = TXT then
	 language := 0
      else
	 language := convert(ffDCB.auxType).lsw;
      buffHandle := pointer(ffDCB.fileHandle);
      buffSize := ffDCB.fileLength;
      size := ffDCB.fileLength;
      ffDCB.action := 6; 		{remove it from the file list}
      ffDCB.pathName := name;
      ffDCB.fileHandle := nil;
      FastFileGS(ffDCB);
      end; {else}
   buffStart := buffHandle^;		{set up initial buffer values}
   buffEnd := pointer(ord4(buffStart)+buffSize);
   gapStart := pointer(ord4(buffStart)+size);
   pageStart := buffStart;
   changed := false;
   changesSinceCompile := true;
   expanded := false;
   cursor := pageStart;
   cursorColumn := 0;
   cursorRow := 0;
   selection := false;
   topLine := 0;
   topLineAlt := topLine+height;
   leftColumn := 0;
   Undo_PopAll;				{delete anything in the undo buffer}
   Expand;				{expand the file buffer}
   if gapStart = pageStart then		{make free room in new files}
      GrowBuffer;
   cp := pointer(ord4(buffEnd)-1);	{make sure the last char is a RETURN}
   if cp^ <> RETURN then
      if gapStart = pageStart then begin
	 OutOfMemory;
	 LoadFile := false;
	 goto 1;
	 end {if}
      else begin
	 Compact;
	 gapStart^ := RETURN;
	 gapStart := pointer(ord4(gapStart)+1);
	 changed := true;
	 Expand;
         FlagError(12, 0);
	 end; {else}
   numLines := 0;			{count the lines in the file}
   cp := buffStart;
   while cp <> gapStart do begin
      if cp^ = return then
	 numLines := numLines+1;
      cp := pointer(ord4(cp)+1);
      end; {while}
   cp := pageStart;
   while cp <> buffEnd do begin
      if cp^ = return then
	 numLines := numLines+1;
      cp := pointer(ord4(cp)+1);
      end; {while}
   end; {with currentFile}
1:
ResetCursor;
end; {LoadFile}


procedure LoadFileStateResources {name: gsosInStringPtr};

{ load the file state resource and set the variables		}
{								}
{ Parameters:							}
{    name - name of the file to load				}

var
   fileState: fileStateRecord;		{file state information}
   fsPtr: fileStatePtr;			{file state pointer}
   i: 0..255;				{loop/index variable}
   port: grafPortPtr;			{caller's grafPort}
   resHandle: handle;			{resource handle}
   fileID: integer;			{resource fork file ID}


   function GetPointer (disp: longint): charPtr;

   { Convert a file displacement to a character pointer		}
   {								}
   { Parameters:						}
   {    disp - file displacement				}
   {								}
   { Returns: character pointer					}

   begin {GetPointer}
   if disp = 0 then
      if currentFile.buffStart = currentFile.gapStart then
         GetPointer := currentFile.pageStart
      else
         GetPointer := currentFile.buffStart
   else begin
      GetPointer := charPtr(disp + ord4(currentFile.buffStart));
      if currentFile.expanded then
         if disp > ord4(currentFile.gapStart) - ord4(currentFile.buffStart) then
            GetPointer := charPtr(disp + ord4(currentFile.buffStart)
               + (ord4(currentFile.pageStart) - ord4(currentFile.gapStart)));
      end; {else}
   end; {GetPointer}


begin {LoadFileStateResources}
fileID := OpenResourceFile(3, nil, name^);
if ToolError = 0 then begin

   {read the resource}
   resHandle := LoadResource(fsResType, fsResID);
   if ToolError = 0 then begin
      HLock(resHandle);
      fsPtr := fileStatePtr(resHandle^);
      if fsPtr^.version = 1 then begin
         if fsPtr^.pCount >= 2 then begin
            currentFile.autoReturn := f_indentedReturns in fsPtr^.flags;
            currentFile.insert := f_insertPRIZM in fsPtr^.flags;
            currentFile.newDebug := f_newDebug in fsPtr^.flags;
            if f_showRuler in fsPtr^.flags then
               DoShowRuler;
            end; {if}
         if fsPtr^.pCount >= 3 then
            currentFile.cursor := GetPointer(fsPtr^.cursor);
         if fsPtr^.pCount >= 4 then begin
            currentFile.select := GetPointer(fsPtr^.select);
            currentFile.selection :=
               ord4(currentFile.select) > ord4(currentFile.cursor);
            end; {if}
         FindCursor;
         if fsPtr^.pCount >= 5 then begin
            with fsPtr^.position do
               if (h2 > h1) and (v2 > v1) then begin
                  if (h1 > 635) or (h2 < 5) then begin
                     h2 := h2 - h1;
                     h1 := 0;
                     end; {if}
                  if (v1 > 195) or (v2 < 25) then begin
                     v2 := 25 + v2 - v1;
                     v1 := 25;
                     end; {if}
                  ResizeWindow(true, fsPtr^.position, currentFile.wPtr);
                  ChangeSize(h2 - h1, v2 - v1, true);
                  end; {if}
            end; {if}
         if fsPtr^.pCount >= 6 then
            currentFile.ruler := fsPtr^.tabs;
         end; {if}
      end; {if}

   FollowCursor;
   CloseResourceFile(fileID);
   end; {if}
end; {LoadFileStateResources}


procedure MoveDown {lines: integer};

{ Move the cursor toward the end of the file			}
{								}
{ Parameters:							}
{    lines - move down this many lines				}

begin {MoveDown}
with currentFile do begin
   if not verticalMove then
      vCursorColumn := cursorColumn;
   if cursorRow+topLine+lines >= numLines then
      lines := ord(numLines-topLine-cursorRow)-1;
   cursorRow := cursorRow+lines;
   MoveCursor(vCursorColumn,lines);
   end; {with}
FollowCursor;
currentFile.verticalMove := true;
end; {MoveDown}


procedure MoveLeft {cols: integer};

{ Move the cursor toward the start of a line			}
{								}
{ Parameters:							}
{    cols - number of columns to move				}

var
   col, lcol: 0..maxint;		{column counters}
   lcursor: charPtr;			{work buffer pointer}

begin {MoveLeft}
currentFile.verticalMove := false;
with currentFile do begin
   cursorColumn := cursorColumn-cols;	{update cursorColumn}
   if cursorColumn < 0 then
      cursorColumn := 0;
   MoveToStart;
   col := 0;
   while col < cursorColumn do begin
      lcol := col;
      lcursor := cursor;
      if cursor^ = return then begin
         col := cursorColumn
         end {if}
      else if cursor^ <> tab then begin
         col := col+1;
         cursor := pointer(ord4(cursor)+1);
         end {else if}
      else begin
         repeat
            col := col+1
         until (col > 255) or (ruler[col] <> 0);
         cursor := pointer(ord4(cursor)+1);
         end; {else}
      end; {while}
   if col > cursorColumn then begin
      cursorColumn := lcol;
      cursor := lcursor;
      end; {if}
   end; {with}
FollowCursor;				{make sure the cursor is visible}
end; {MoveLeft}


procedure MoveRight {cols: integer};

{ Move the cursor toward the end of a line			}
{								}
{ Parameters:							}
{    cols - number of columns to move				}

var
   i: integer;				{loop variable}

begin {MoveRight}
currentFile.verticalMove := false;
with currentFile do begin		{update cursorColumn}
   if cols < 0 then cols := 0;
   while cols <> 0 do begin
      cursorColumn := cursorColumn+1;
      cols := cols-1;
      if cursor^ <> return then begin
         if cursor^ = tab then begin
            while ruler[cursorColumn] = 0 do begin
               cursorColumn := cursorColumn+1;
               cols := cols-1;
               end; {while}
            if cols < 0 then cols := 0;
            end; {if}
         cursor := pointer(ord4(cursor)+1);
         end; {if}
      end; {while}
   if cursorColumn > 255 then begin
      cursorColumn := 255;
      MoveCursor(cursorColumn,0);
      end; {if}
   end; {with}
FollowCursor;				{make sure the cursor is visible}
end; {MoveRight}


procedure MoveUp {lines: integer};

{ Move the cursor toward the start of the file			}
{								}
{ Parameters:							}
{    lines - move up this many lines				}

begin {MoveUp}
with currentFile do begin
   if not verticalMove then
      vCursorColumn := cursorColumn;
   if cursorRow+topLine-lines >= 0 then begin
      cursorRow := cursorRow-lines;
      MoveCursor(vCursorColumn,-lines);
      end {if}
   else begin
      cursorRow := -topLine;
      MoveCursor(vCursorColumn,-topLine);
      end; {else}
   end; {with}
FollowCursor;
currentFile.verticalMove := true;
end; {MoveUp}


procedure OpenNewWindow {x,y,w,h: integer; name: gsosInStringPtr};

{ open a window							}
{								}
{ Parameters:							}
{    x,y - location of the window				}
{    w,h - size of the window					}
{    name - name of the window					}

label 1;

var
   lInsert: boolean;			{temp variables for loading a file}
   lAutoReturn: boolean;
   lLanguage: integer;
   lRec: langDCBGS;			{Get_Lang record}
 
   fp: buffPtr;				{file buffer poiner; for checking to   }
					{ see if a window already exists       }
   r: rect;				{for locating controls}
 
 
   procedure FindFileName (var fileName: string33; pathName: gsosInStringPtr);

   { given the path name, find the file name			}
   {								}
   { Parameters: 						}
   {	fileName - file name					}
   {	pathName - path name					}
 
   var
      i,j,k: unsigned;			{index variables}

   begin {FindFileName}
   i := pathName^.size;
   while (pathName^.theString[i] <> ':') and (i > 0) do
      i := i-1;
   if pathName^.theString[i] = ':' then
      i := i+1;
   j := 0;
   for k := i to pathName^.size do begin
      j := j+1;
      if j < 33 then
         fileName[j] := pathName^.theString[k];
      end; {for}
   fileName[0] := chr(j);
   fileName := concat(' ', fileName, ' ');
   end; {FindFileName}


begin {OpenNewWindow}
if filePtr <> nil then begin		{save info from the old file, if any}
   Compact;
   currentPtr^ := currentFile;
   with currentFile do begin
      lInsert := insert; 		{set default flags based on active file}
      lAutoReturn := autoReturn;
      lLanguage := language;
      end; {with}
   fp := filePtr;			{make sure the window isn't open       }
   while fp <> nil do begin		{ already			       }
      if fp^.isFile then
	 if OSStringsEqual(@fp^.pathName, name) then
	    if FindActiveFile(fp^.wPtr) then begin
	       SelectWindow(currentFile.wPtr);
	       CheckWindow(currentFile.wPtr);
	       goto 1;
	       end; {if}
      fp := fp^.next;
      end; {while}
   end {if}
else begin
   lInsert := true;			{set default flags}
   lAutoReturn := false;
   lRec.pcount := 1;
   GetLangGS(lRec);
   lLanguage := lRec.lang;
   end; {else}
new(currentPtr); 			{set up a new file buffer}
if currentPtr = nil then begin
   if filePtr <> nil then
      if FindActiveFile(filePtr^.wPtr) then ;
   OutOfMemory;
   goto 1;
   end; {if}
if filePtr <> nil then
   filePtr^.last := currentPtr;
with currentFile do begin
   last := nil;
   next := filePtr;
   end; {with}
filePtr := currentPtr;
with currentFile do begin
   FindFileName(fileName,name);		{get the file name}
   currentPtr^ := currentFile;		{create the window}
   wPtr := NewWindowFrame(x,y-25,w,h,grafPortPtr(-1),false,@currentPtr^.fileName);
   StartDrawing(wPtr);			{make this the current window}
   pathName := name^;			{set the path name}
   height := (h-hScrollHeight) div chHeight; {set the default screen size}
   width := w div chWidth - 4;
   maxHeight := h-(hScrollHeight-1);	{height of screen in pixels}
   dispFromTop := 0;			{no split screen}
   splitScreen := false;
   vScrollAlt := nil;
   showRuler := false;			{the ruler is not visible}
   undoList := nil;			{nothing to undo}
   language := lLanguage;		{set the defaults}
   insert := lInsert;
   autoReturn := lAutoReturn;
   verticalMove := false;
					{load the file}
   if LoadFile(name) then
      SetTabs(language,insert,autoReturn,ruler,newDebug)
   else begin {file not loaded}

      {Error during load - shut down this window}
      CloseWindow(wPtr);
      filePtr := currentPtr^.next;
      if filePtr <> nil then
	 filePtr^.last := nil;
      dispose(currentPtr);
      currentPtr := nil;
      if filePtr <> nil then
	 if FindActiveFile(filePtr^.wPtr) then ;
      goto 1;
      end; {else}
   SetInfoRefCon(ord4(currentPtr),wPtr); {set the reference value}
   r.h1 := 0; r.h2 := w; 		{create the controls}
   r.v1 := 0; r.v2 := h;
   CreateControls(@r);
   SetContentDraw(@UpdateAWindow,wPtr); {set up the content routine}
   currentPtr^ := currentFile;		{save info}
   AddWindow2(wPtr);			{put it in the window list}
   LoadFileStateResources(name);	{load file details}
   currentPtr^ := currentFile;		{save info}
   end; {with}
1:
CheckMenuItems;
end; {OpenNewWindow}


procedure Position {column,row: integer};

{ Position cursor - stays on screen!				}
{								}
{ Parameters:							}
{    column - column to place the cursor 			}
{    row - row to place the cursor				}
{								}
{ NOTE: row must be positive					}

var
   i: integer;				{loop variable}

begin {Position}
currentFile.verticalMove := false;
with currentFile do begin
   if topLine+row >= numLines then
      row := ord(numLines-topLine)-1;
   cursorColumn := column;
   cursorRow := row;
   cursor := pageStart;
   MoveCursor(column,row);
   end; {with}
FollowCursor;
end; {Position}


procedure ReplaceAll {search,replace: searchString;
   whole,caseFlag,fold: boolean};

{ Global search & replace, no checking				}
{								}
{ Parameters:							}
{    search - search string					}
{    replace - replace string					}
{    whole - whole word? 					}
{    caseFlag - case sensitive?					}
{    fold - fold whitespace?					}

var
   lCursorColumn: integer;		{local copies of variables}
   lTopLine,lCursorRow: longint;
   lastCursor: charPtr;			{...to check for completion}

begin {ReplaceAll}
currentFile.verticalMove := false;
with currentFile do begin
   WaitCursor;				{switch to watch cursor}
   disableScreenUpdates := true; 	{make sure the screen doesn't flicker}
   lCursorRow := cursorRow;		{save the cursor position}
   lTopLine := topLine;
   lCursorColumn := cursorColumn;
   ScrollUp(topLine);			{move to the top of the file}
   cursor := pointer(ord4(buffEnd)-1);
   FindCursor;
   lastCursor := pageStart;		{replace all strings}
   Find(search,whole,caseFlag,fold,true);
   if cursor <> pointer(ord4(buffEnd)-1) then
      while ord4(lastCursor) < ord4(cursor) do begin
	 DoPaste(false,pointer(ord4(@replace)+1),ord(replace[0]));
	 lastCursor := cursor;
	 Find(search,whole,caseFlag,fold,false);
	 end; {while}
   if lTopLine > topLine then		{move the file back to the screen}
      ScrollDown(lTopLine-topLine)
   else
      ScrollUp(topLine-lTopLine);
   cursor := pageStart;			{reposition the cursor}
   MoveCursor(lCursorColumn,lCursorRow);
   cursorColumn := lCursorColumn;
   cursorRow := lCursorRow;
   disableScreenUpdates := false;	{enable screen updates & repaint}
   DrawScreen;
   ResetCursor;
   FollowCursor;
   end; {with}
end; {ReplaceAll}


procedure ResetCursor;

{ switch to the arrow cursor					}
{								}
{ Notes: Defined externally in PCommon				}

begin {ResetCursor}
TrackCursor(-1,-1,10,10,true);
end; {ResetCursor}


procedure SaveFile {paction: integer};

{ save the current file						}
{								}
{ Parameters:							}
{    paction - FastFile action to take after the save		}

var
   fiDCB: getFileInfoOSDCB;		{DCB for setting language}
   siDCB: setFileInfoOSDCB;		{DCB for setting language}
   cpDCB: changePathOSDCB; 		{DCB for renaming file}
   ffDCB: fastFileDCBGS;		{DCB for file load}

   i: unsigned;				{loop/index variable}
   size: longint;			{size of the file}


   procedure SaveResources;

   { Save the file state resource				}

   var
      fileState: fileStateRecord;	{file state information}
      fsPtr: fileStatePtr;		{file state pointer}
      i: 0..255;			{loop/index variable}
      port: grafPortPtr;		{caller's grafPort}
      resHandle: handle;		{resource handle}
      fileID: integer;			{resource fork file ID}
      temp: longint;			{swap variable for cursor, select}


      function GetDisplacement (pos: longint): longint;

      { Convert a character pointer to a file displacement	}
      {								}
      { Parameters:						}
      {    pos - character pointer				}
      {								}
      { Returns: file displacement				}

      begin {GetDisplacement}
      GetDisplacement := ord4(pos) - ord4(currentFile.buffStart);
      if currentFile.expanded then
         if ord4(pos) > ord4(currentFile.gapStart) then
            GetDisplacement := ord4(pos) - ord4(currentFile.buffStart)
               - (ord4(currentFile.pageStart) - ord4(currentFile.gapStart));
      end; {GetDisplacement}


   begin {SaveResources}
   CreateResourceFile(0, 0, 0, currentFile.pathName);
   fileID := OpenResourceFile(3, nil, currentFile.pathName);
   if ToolError = 0 then begin

      {set up necessary defaults for the file state record}
      fileState.flags := [];

      {read the existing resource}
      resHandle := LoadResource(fsResType, fsResID);
      if ToolError = 0 then begin
         HLock(resHandle);
         fsPtr := fileStatePtr(resHandle^);
         if fsPtr^.version = 1 then
            if fsPtr^.pCount >= 2 then
               fileState.flags := fsPtr^.flags;

         {delete the old resource}
         RemoveResource(fsResType, fsResID);
         end; {if}

      {set up the new resource record}
      with fileState do begin
         pCount := 6;
         version := 1;
         flags := flags - [f_indentedReturns, f_insertPRIZM, f_newDebug, f_showRuler];
         if currentFile.autoReturn then
            flags := flags + [f_indentedReturns];
         if currentFile.insert then
            flags := flags + [f_insertPRIZM];
         if currentFile.newDebug then
            flags := flags + [f_newDebug];
         if currentFile.showRuler then
            flags := flags + [f_showRuler];
         cursor := GetDisplacement(currentFile.cursor);
         if currentFile.selection then begin
            select := GetDisplacement(currentFile.select);
            if select < cursor then begin
               temp := select;
               select := cursor;
               cursor := temp;
               end; {if}
            end {if}
         else
            select := cursor;
         port := GetPort;
         SetPort(currentFile.wPtr);
         GetPortRect(position);
         LocalToGlobal(position.topLeft);
         LocalToGlobal(position.botRight);
         SetPort(port);
         tabs := currentFile.ruler;
         end; {with}

      {stuff the resource record into a handle}
      resHandle := NewHandle(sizeof(fileStateRecord), UserID, $8010, nil);
      if resHandle <> nil then begin
         fsPtr := fileStatePtr(resHandle^);
         fsPtr^ := fileState;
         HUnlock(resHandle);

         {add the new resource}
         AddResource(resHandle, resChanged+attrNoCross, fsResType, fsResID);
         end; {if}

      CloseResourceFile(fileID);
      end; {if}
   end; {SaveResources}


begin {SaveFile}
with currentFile do
   if changed then begin 		{don't save if there are no changes}
      WaitCursor;			{this takes time...}
      Compact;				{make the buffer contiguous}
      with ffDCB do begin		{fill in the info}
         pcount := 14;
	 action := 3;
	 flags := $C000;
	 fileHandle := pointer(buffHandle);
	 pathName := @currentFile.pathName;
	 access := $C3;
	 if language = 0 then
	    fileType := TXT
	 else
	    fileType := SRC;
	 auxType := language;
	 if language < 0 then
	     auxType := auxType & $0000FFFF;
	 storageType := 1;
         for i := 1 to 8 do
            createDate[i] := 0;
	 modDate := createDate;
         option := nil;
	 fileLength := ord4(gapStart)-ord4(buffStart);
	 end; {with}
      FastFileGS(ffDCB);		{write the file}
      if ToolError <> 0 then		{note an error if there was one}
	 FlagError(13, ToolError)
      else
	 changed := false;		{no recent changes}
      ffDCB.action := paction;		{remove or purge the file}
      ffDCB.pathName := @currentFile.pathName;
      FastFileGS(ffDCB);
					{make sure the language stamp is correct}
      fiDCB.pcount := 12;
      fiDCB.pathName := @currentFile.pathName;
      fiDCB.optionList := nil;
      GetFileInfoGS(fiDCB);
      if ToolError = 0 then begin
         siDCB.pcount := 4;
         siDCB.pathName := @currentFile.pathName;
         siDCB.access := fiDCB.access;
	 if language = 0 then
	    siDCB.fileType := TXT
	 else
	    siDCB.fileType := SRC;
	 siDCB.auxType := language;
	 if language < 0 then
	     siDCB.auxType := language & $0000FFFF;
	 SetFileInfoGS(siDCB);
	 end; {if}      
      SaveResources;			{save the file state resource}
					{preserve case of file name}
      cpDCB.pcount := 2;
      cpDCB.pathName := @currentFile.pathName;
      cpDCB.newPathName := @currentFile.pathName;
      ChangePathGS(cpDCB);
      if paction <> 7 then		{get the buffer ready for edits}
	 Expand;
      ResetCursor;			{back to the arrow...}
      end; {if}
end; {SaveFile}


procedure ShiftLeft;

{ Shift the selected text left one column			}

var
   cp1: charPtr; 			{work character pointer}
   lCursor: charPtr;			{temp copy of cursor}
   startCursor: boolean; 		{is the cursor at the start of a line?}
 
 
   procedure RemoveACHaracter;
 
   { Delete a character and do necessary book keeping		 }
 
   var
      cc: 0..maxint;			{column counter}
      cp: charPtr;			{work pointer}
      i: 0..maxint;			{loop counter}

   begin {RemoveACharacter}
   with currentFile do  begin
      if cursor^ = tab then begin
	 while cursor^ = tab do
	    cursor := pointer(ord4(cursor)+1);
         if cursor^ <> ord(' ') then begin
            cc := FindCursorColumn;
	    cursor := pointer(ord4(cursor)-1);
            cc := cc - FindCursorColumn;
            cursor^ := ord(' ');
            for i := 2 to cc do begin
	       if InsertChar then begin
		  cp := pointer(ord4(cursor)-1);
		  cp^ := ord(' ');
                  end; {if}
	       if startCursor then
		  lCursor := pointer(ord4(lCursor)-1);
               end; {for}
            end; {if}
         end; {if}
      if cursor^ = ord(' ') then begin
	 cursor := pointer(ord4(cursor)+1);
	 DeleteACharacter;
	 if cursor = select then
	    selection := false;
	 if startCursor then
	    lCursor := pointer(ord4(lCursor)+1);
	 cursorColumn := cursorColumn+1;
	 end; {if}
      end; {with}
   end; {RemoveACharacter}


begin {ShiftLeft}
currentFile.verticalMove := false;
with currentFile do
   if selection then begin
      WaitCursor;
      if ord4(cursor) > ord4(select) then begin
	 cp1 := cursor;
	 cursor := select;
	 select := cp1;
	 FindCursor;
	 end; {if}
      FollowCursor;
      lCursor := cursor;
      MoveToStart;
      startCursor := cursor = lCursor;
      cp1 := cursor;
      RemoveACharacter;
      cp1 := cursor;
      cursor := pointer(ord4(cursor)+1);
      while ord4(cursor) < ord4(select) do begin
	 if (cp1^ = return) then
	    RemoveACharacter;
	 cp1 := cursor;
	 cursor := pointer(ord4(cursor)+1);
	 end; {while}
      cursor := lCursor;
      FindCursor;
      DrawScreen;
      ResetCursor;
      end; {if}
end; {ShiftLeft}


procedure ShiftRight;

{ Shift the selected text right one column			}

var
  cp1: charPtr;				{work character pointer}
  lCursor: charPtr;			{temp copy of cursor}
  startCursor: boolean;			{is the cursor at the start of a line?}


   procedure InsertBlank;

   { insert a blank at the current cursor position		}

   var
      cp: charPtr;			{work pointer}

   begin {InsertBlank}
   with currentFile do begin
      while cursor^ = tab do
         cursor := pointer(ord4(cursor)+1);
      if InsertChar then begin
	 cp := pointer(ord4(cursor)-1);
	 cp^ := ord(' ');
	 if startCursor then
	    lCursor := pointer(ord4(lCursor)-1);
	 Check255;
	 end; {if}
      end; {with}
   end; {InsertBlank}


begin {ShiftRight}
currentFile.verticalMove := false;
with currentFile do
   if selection then begin
      WaitCursor;
      if ord4(cursor) > ord4(select) then begin
	 cp1 := cursor;
	 cursor := select;
	 select := cp1;
	 FindCursor;
	 end; {if}
      FollowCursor;
      lCursor := cursor;
      MoveToStart;
      startCursor := cursor = lCursor;
      InsertBlank;
      cp1 := cursor;
      cursor := pointer(ord4(cursor)+1);
      while ord4(cursor) < ord4(select) do begin
	 if cp1^ = return then
	    InsertBlank;
	 cp1 := cursor;
	 cursor := pointer(ord4(cursor)+1);
	 end; {while}
      cursor := lCursor;
      FindCursor;
      DrawScreen;
      ResetCursor;
      end; {if}
end; {ShiftRight}


procedure SplitTheScreen {v: integer; portR: rect};

{ split the screen at v						}
{								}
{ Parameters:							}
{    v - 							}
{    portR -							}

var
   splitTopLine: longint;		{topLineAlt at old split}
   useLower: boolean;			{use the lower half of the screen?}
   wasSplit: boolean;			{was the screen already split?}

begin {SplitTheScreen}
with currentFile do begin
   useLower := dispFromTop <> 0;
   if useLower then			{make sure we are using the top half}
      SwitchSplit;
   wasSplit := splitScreen;		{save the old split (if any)}
   splitTopLine := topLineAlt;
   if vScrollAlt <> nil then		{redo the controls}
      DisposeControl(vScrollAlt);
   if vScroll <> nil then begin
      DisposeControl(vScroll);
      DisposeControl(hScroll);
      DisposeControl(grow);
      end; {if}
   if (v > portR.v2) or (v = 0)		{if off screen, get rid of split}
      or (portR.v2 < 10*chHeight+5) then begin
      splitScreen := false;		{disable split}
      vScrollAlt := nil;
      height := (portR.v2-hScrollHeight) div chHeight;
      end {if}
   else begin				{create a split}
      if not splitScreen then		{if cursor in bottom half, make active}
	 if cursorRow > height then
	    useLower := true;
      splitScreen := true;		{set up the split screen variables}
      if v < 5*chHeight then v := 5*chHeight;
      if v > portR.v2-(5*chHeight+hScrollHeight) then
	 v := portR.v2-(5*chHeight+hScrollHeight);
      height := v div chHeight;
      dispFromTopAlt := height*chHeight+3;
      heightAlt := (portR.v2-dispFromTopAlt-2-hScrollHeight) div chHeight;
      if wasSplit then
	 topLineAlt := splitTopLine
      else begin
	 topLineAlt := topLine+height;
	 if topLineAlt > numLines-1 then
	    topLineAlt := numLines-1;
	 end; {else}
      end; {else}
   EraseRect(portR);			{clear the screen}
   CreateControls(@portR);		{create the new controls}
   DrawControls(wPtr);
   if splitScreen then			{reset the control values}
      SetCtlValue(max2(topLineAlt),vScrollAlt);
   SetCtlValue(max2(topLine),vScroll);
   if not splitScreen then		{scroll, if needed}
      if wasSplit then
	 if useLower then
	    if splitTopLine > topLine then
	       ScrollDown(splitTopLine-topLine)
	    else
	       ScrollUp(topLine-splitTopLine);
   DrawScreen;				{draw the text}
   if useLower then			{check to see if lower half is active}
      SwitchSplit;
   end; {with}
end; {SplitTheScreen}


procedure SwitchSplit;

{ switch the active half of the split screen			}

var
   l: longint;				{temp var}
   i: integer;				{temp var}
   ch: ctlRecHndl;			{temp var}

begin {SwitchSplit}
with currentFile do
   if splitScreen then begin
      i := height; height := heightAlt; heightAlt := i;
      i := dispFromTop; dispFromTop := dispFromTopAlt; dispFromTopAlt := i;
      ch := vScroll; vScroll := vScrollAlt; vScrollAlt := ch;
      disableScreenUpdates := true;
      l := topLineAlt; topLineAlt := topLine;
      if l > topLine then
	 ScrollDown(l-topLine)
      else
	 ScrollUp(topLine-l);
      disableScreenUpdates := false;
      DrawScreen;
      end; {if}
end; {SwitchSplit}


procedure TabChar {left: boolean};

{ move to a new tab stop 					}
{								}
{ Parameters:							}
{    left - tab left?						}

var
   cp: charPtr;				{temp buffer pointer}
   oldLeftColumn: integer;		{local copy of leftColumn}
   r: rect;				{for repainting ruler}
   update: boolean;			{local copy of disableScreenUpdates}

begin {TabChar}
currentFile.verticalMove := false;
FollowCursor;
with currentFile do begin
   oldLeftColumn := leftColumn;
   DeleteSelection;
   update := disableScreenUpdates;
   disableScreenUpdates := true;
   if left then
      repeat
	 MoveLeft(1)
      until (cursorColumn = 0) or (ruler[cursorColumn] <> 0)
   else
      if insert or (cursor^ = return) then begin
	 BlankExtend;			{if needed, add spaces to EOL}
	 if InsertChar then begin	{insert a space in the buffer}
	    cp := pointer(ord4(cursor)-1); {place the char in the buffer}
	    cp^ := tab;
	    MoveCursor(cursorColumn+1, 0); {advance the cursor}
	    Check255;			{clip lines that are too long}
	    end; {if}
         end {if}
      else
	 repeat
	    MoveRight(1)
	 until (ruler[cursorColumn] <> 0) or (cursorColumn > 254);
   disableScreenUpdates := update;
   if oldLeftColumn <> leftColumn then begin
      DrawScreen;
      SetCtlValue(leftColumn,hScroll);
      if showRuler then begin
	 currentPtr^ := currentFile;
	 StartInfoDrawing(r,wPtr);
	 DrawRuler(r,ord4(@currentFile),wPtr);
	 EndInfoDrawing;
	 end; {if}
      end {if}
   else
      DrawLine(convert(cursorRow).lsw);
   end; {with}
end; {TabChar}


{$DataBank+}

procedure UpdateAWindow;

{ update the current window					}

var
   lbusy,ldisablescreenupdates: boolean; {temp storage}
   wp,owp: grafPortPtr;			{window pointer work variables}
   r: rect;				{current rectangle}

begin {UpdateAWindow}
wp := grafPortPtr(GetPort);		{find the window we need to update}
lbusy := busy;				{prevent interupts}
busy := true;
ldisablescreenupdates := disableScreenUpdates; {allow screen draws}
disableScreenUpdates := false;
if cursorVisible then Blink;		{hide insertion point}
owp := currentFile.wptr;
if FindActiveFile(wp) then
   with currentFile do begin
      GetPortRect(r);			{update the size}
      if (r.h2 div chWidth -4 <> width) or
	 ((r.v2-(hScrollHeight-1)) div chHeight <> maxHeight) then
	 ChangeSize(r.h2,r.v2,true)
      else
	 DrawControls(currentFile.wPtr); {redraw the controls}
      DrawScreen;			{draw the screen}
      SetPenMode(0);			{draw the split screen control}
      DrawSplitScreenControl(splitScreenRect,splitScreen);
      end; {with}
if FindActiveFile(owp) then ;		{back to the original window...}
busy := lbusy;				{restore original flags}
disableScreenUpdates := ldisablescreenupdates;
end; {UpdateAWindow}

{$DataBank-}


procedure Undo_Delete {num: longint};

{ copies num characters, starting at the cursor, to the current }
{ undo record							}
{								}
{ Parameters:							}
{    num - number of characters to save				}

label 1;

var
   pos: longint; 			{position of insert}
   source: longint;			{temp var for move calculations}
   ub: undoPtr;				{pointer to the current undo record}
 
 
   procedure SetBuffSize (size: longint);

   { make sure the buffer is at least size long			}
   {								}
   { Parameters: 						}
   {	size - min buffer size					}
 
   const
      undoBuffSize	  = 512; 	{chunk size of undo buffer}
 
   var
      newH: charHandle;			{handle of the new buffer}
      newSize: longint;			{size of the new buffer}
      ub: undoPtr;			{pointer to the current undo record}
 
   begin {SetBuffSize}
   ub := currentFile.undoList;
   with ub^ do
      if deleteSize < size then begin
	 newSize := deleteSize;
	 while newSize < size do
	    newSize := newSize+undoBuffSize;
	 newH := pointer(NewHandle(newSize,userID,$8300,nil));
	 if ToolError <> 0 then begin
	    OutOfMemory;
	    goto 1;
	    end; {if}
	 if deleteSize <> 0 then begin
	    MoveBack(deleteHandle^,newH^,deleteChars);
	    DisposeHandle(deleteHandle);
	    end; {if}
	 deleteHandle := newH;
	 deleteSize := size;
	 end; {if}
   end; {SetBuffSize}


begin {Undo_Delete}
currentFile.verticalMove := false;
if not doingUndo then
   with currentFile do begin
      if undoList = nil then		{allocate a buffer if there is none}
	 Undo_New;
      ub := undoList;			{if the current buffer has inserted }
      if ub^.insertChars <> 0 then	{ chars, get a new one		    }
	 begin
	 Undo_New;
	 ub := undoList;
	 end; {if}
      pos := ord4(cursor)-ord4(buffStart)+ord4(gapStart)-ord4(pageStart);
      if ub^.deleteChars <> 0 then	{new record if the deletes are in   }
	 if pos+num <> ub^.deletePos	{ different spots		    }
	    then begin
	    Undo_New;
	    ub := undoList;
	    SetBuffSize(num);
	    end {if}
	 else with ub^ do begin		  {if the records are in the same     }
	    SetBuffSize(deleteChars+num); { spot, move the old chars over     }
	    source := ord4(deleteHandle^)+deleteChars;
	    MoveForward(pointer(source),pointer(source+num),deleteChars);
	    end {with}
      else
	 SetBuffSize(num);		{get a buffer that's long enough}
      with ub^ do begin			{save the characters}
	 MoveBack(cursor,deleteHandle^,num);
	 deleteChars := deleteChars+num;
	 deletePos := pos;
	 end; {with}
      end; {with}
1:
end; {Undo_Delete}


procedure Undo_Insert {num: longint};

{ notes that num characters are about to be inserted into the	}
{ file at the cursor location.					}
{								}
{ Parameters:							}
{    num - number of characters to save				}

var
   pos: longint; 			{position of insert}
   ub: undoPtr;				{pointer to the current undo record}

begin {Undo_Insert}
currentFile.verticalMove := false;
if not doingUndo then
   with currentFile do begin		{compute position where chars go}
      pos := ord4(cursor)-ord4(buffStart)+ord4(gapStart)-ord4(pageStart);
      if undoList = nil then		{allocate a buffer if there is none}
	 Undo_New;
      ub := undoList;
      if ub^.insertChars <> 0 then	{if inserting at new spot then...}
	 begin
	 if pos <> ub^.insertPos then begin
	    Undo_New;			{get a new record}
	    ub := undoList;
	    end; {if}
	 end {if}
      else				{if this is the first insert ...}
	 if ub^.deleteChars <> 0 then	{and there has been a delete ...}
	    if pos <> ub^.deletePos	{to a different spot then	}
	       then begin		{get a new record.		}
	       Undo_New;
	       ub := undoList;
	       end; {if}
      with ub^ do begin			{record the new insert}
	 if insertChars = 0 then
	    insertCol := cursorColumn;
	 insertChars := insertChars+num;
	 insertPos := pos+num;
	 end; {with}
      end; {with}
end; {Undo_Insert}


procedure Undo_New;

{ Pushes the current undo record (if any) and creates a new one }

var
   undoBuff,ub: undoPtr; 		{work pointers}

begin {Undo_New}
currentFile.verticalMove := false;
if not doingUndo then begin
   undoBuff := currentFile.undoList;
   if undoBuff <> nil then		{if there is an old record...}
      if undoBuff^.deleteChars <> 0 then {and it has an undo buffer, then}
	 HUnlock(undoBuff^.deleteHandle); {mark it movable, purgable}
   new(ub);				{create a new undo buffer}
   ub^.next := undoBuff; 		{place the new rec at the head of the }
   currentFile.undoList := ub;		{ linked list			      }
   with ub^ do begin			{initialize the new record}
      insertChars := 0;
      deleteChars := 0;
      deleteSize := 0;
      end; {with}
   end; {if}
end; {Undo_New}


procedure Undo_Pop;

{ pops the top undo record from the undo stack			}

var
   ub: undoPtr;				{work pointer}

begin {Undo_Pop}
ub := currentFile.undoList;
if ub <> nil then begin			{if there is an undo record then...}
   if ub^.deleteChars <> 0 then		{if there is a buffer, dispose of it}
      DisposeHandle(ub^.deleteHandle);
   currentFile.undoList := ub^.next;	{remove the record from the list}
   dispose(ub);				{dispose of the record}
   ub := currentFile.undoList;		{lock the old record}
   if ub <> nil then
      if ub^.deleteChars <> 0 then begin
	 HLock(ub^.deleteHandle);
	 if ub^.deleteHandle^ = nil then {if the record has been purged, pop }
	    Undo_PopAll; 		 { all subsequent records	     }
	 end; {if}
   end; {if}
end; {Undo_Pop}


procedure Undo_PopAll;

{ pop all undo records from the list				}

begin {Undo_PopAll}
while currentFile.undoList <> nil do
   Undo_Pop;
end; {Undo_PopAll}


procedure WordTabLeft;

{ move left to the start of the previous word			}

label 1;

var
   min: charPtr; 			{min char in current text block}

begin {WordTabLeft}
currentFile.verticalMove := false;
with currentFile do begin
   if ord4(cursor) < ord4(gapStart) then
      min := buffStart
   else
      min := pageStart;
   if (cursor <> min) then
      cursor := pointer(ord4(cursor)-1);
   while cursor^ in [return,space,tab] do begin
      if cursor = min then
	 if min = buffStart then goto 1
	 else begin
	    if gapStart = buffStart then goto 1;
	    cursor := pointer(ord4(gapStart)-1);
	    min := buffStart;
	    end; {else}
      if cursor^ = return then
	 cursorRow := cursorRow-1;
      cursor := pointer(ord4(cursor)-1);
      end; {while}
   while (cursor <> min) and (not (cursor^ in [return,space,tab])) do
      cursor := pointer(ord4(cursor)-1);
   if cursor^ in [return,space,tab] then
      cursor := pointer(ord4(cursor)+1);
1:
   FindCursor;
   end; {with}
FollowCursor;
end; {WordTabLeft}


procedure WordTabRight;

{ move right to the start of the next word			}

label 1;

var
   max: charPtr; 			{max char in current text block}

begin {WordTabRight}
currentFile.verticalMove := false;
with currentFile do begin
   if ord4(cursor) < ord4(gapStart) then
      max := gapStart
   else
      max := buffEnd;
   while not (cursor^ in [return,tab,space]) do 
      cursor := pointer(ord4(cursor)+1);
   while cursor^ in [return,tab,space] do begin
      if cursor^ = return then
	 cursorRow := cursorRow+1;
      cursor := pointer(ord4(cursor)+1);
      if cursor = max then
	 if max = gapStart then begin
	    max := buffEnd;
	    cursor := pageStart;
	    end {if}
	 else begin
	    cursor := pointer(ord4(buffEnd)-1);
	    FindCursor;
	    goto 1;
	    end; {else}
      end; {while}
   1:
   cursorColumn := FindCursorColumn;
   FollowCursor;
   end; {with}
end; {WordTabRight}

end.

{$Append 'buffer.asm'}
