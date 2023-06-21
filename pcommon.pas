{$optimize 7}
{---------------------------------------------------------------}
{								}
{  Common - Primitive procedures, variables and types used by	}
{	    multiple units.					}
{								}
{  By Mike Westerfield						}
{								}
{  Copyright 1987						}
{  Byte Works, Inc.						}
{								}
{---------------------------------------------------------------}
unit Common;

interface

{$segment 'Prism'}

uses Common, QuickDrawII, EventMgr, WindowMgr, DialogMgr, MenuMgr, ResourceMgr,
   MemoryMgr, ControlMgr;

const
					{misc}
					{----}
   base		=	$07FE0000;	{base resource ID number}
   maxNameLen	=	256;		{max length of a file name}
   osBuffLen	=	253;		{length of a GS/OS file buffer}
   osMaxSize	=       258;		{buffer size of output strings}
   rWindParam1	=	$800E;		{resource ID}

					{menu names/numbers}
   apple_About			= 257;

   file_New			= 260;
   file_Open			= 261;
   file_Close			= 255;
   file_Save			= 263;
   file_SaveAs			= 264;
   file_RevertToSaved		= 265;
   file_PageSetup		= 270;
   file_Print			= 272;
   file_Quit			= 273;

   edit_Undo			= 250;
   edit_Cut			= 251;
   edit_Copy			= 252;
   edit_Paste			= 253;
   edit_Clear			= 254;
   edit_SelectAll		= 285;
   edit_ShowClipboard		= 286;

   windows_Tile			= 300;
   windows_Stack 		= 301;
   windows_Shell 		= 302;

   find_Find			= 520;
   find_FindSame 		= 521;
   find_DisplaySelection 	= 522;
   find_Replace			= 523;
   find_ReplaceSame		= 524;
   find_Goto			= 525;
 
   extras_ShiftLeft		= 530;
   extras_ShiftRight		= 531;
   extras_DeleteToEndOfLine	= 532;
   extras_JoinLines		= 533;
   extras_InsertLine		= 534;
   extras_DeleteLine		= 535;
   extras_AutoIndent		= 536;
   extras_OverStrike		= 537;
   extras_ShowRuler		= 538;
   extras_AutoSave		= 539;
 
   run_CompileToMemory		= 540;
   run_CompileToDisk		= 541;
   run_CheckForErrors		= 542;
   run_GraphicsWindow		= 543;
   run_Compile			= 544;
   run_Link			= 545;
   run_Execute			= 546;
   run_ExecuteOptions		= 547;
 
   debug_Step			= 550;
   debug_StepThru		= 551;
   debug_Trace			= 552;
   debug_Go			= 553;
   debug_GoToNextReturn		= 554;
   debug_Stop			= 555;
   debug_Profile 		= 556;
   debug_SetClearBreakPoint	= 557;
   debug_SetClearAutoGo		= 558;
   debug_Variables		= 559;
 
   languages_Shell		= 570;

   RETURN	=	$0D;		{key codes}
   TAB		=	$09;
   UpArrowKey	=	$0B;
   DownArrowKey =	$0A;
   space 	=	$20;
   deleteCh	=	$7F;
   oldAutoGo	=	$81;		{old auto-go marker}
   oldBreakPoint =	$84;		{old break point marker}
   stepChar	=	$05;		{step and trace arrow character}
   newAutoGo	=	$06;		{new auto-go marker}
   newBreakPoint =	$07;		{new break point marker}

   WPF		=	$0B;		{file type numbers}
   AWP		=	$1A;
   SRC		=	$B0;
   TXT		=	$04;
   LIB		=	$B2;
   CDA		=	$B9;
   NDA		=	$B8;
   S16		=	$B3;
   EXE		=	$B5;
   SYS		=	$FF;
   DIR		=	$0F;
   ADB		=	$19;
   ASP		=	$1B;
   FNT		=	$07;
   FT2		=	$C8;
   OBJ		=	$B1;

type
					{misc}
					{----}
   long = record lsw,msw: integer; end;	 {for picking words from longints}
   menuStateType =			{menu highlight state}
      (nullMenu,noWindow,sysWindow,execMenu,specWindow,noSelection,fullMenu);
   unsigned = 0..maxint;		{unsigned integer}

					{window & menu numbering}
					{-----------------------}
   languageRecPtr = ^languageRec;	{languages record}
   languageRec = record
      next: languageRecPtr;		{next entry}
      name: string[15];			{name of the language}
      number: integer;			{language number}
      restart: boolean;			{is the compiler restartable?}
      menuItem: integer; 		{menu item number}
      menuName: packed array[1..24] of char; {menu item name}
      end;

   windowMenuListPtr = ^windowMenuListElement;
   windowMenuListElement = record	{menu window list element}
      next,last: windowMenuListPtr;
      menuID: integer;
      menuItem: packed array[1..80] of char;
      wPtr: grafPortPtr;
      end;

{------------------------------------------------------------------------------}

var
					{misc}
					{----}
   msg: pString; 			{for building alert messages}
   startStopParm: longint;              {tool start/shutdown parameter}
   screenPtr: ptr;                      {pointer to screen memory}

					{window & menu numbering}
					{-----------------------}
   lastUntitledNum: integer;		{number of last untitled window}
   languages: languageRecPtr;		{head of languages list}
   windowMenuList: windowMenuListPtr;	{list of window/menu correspondences}

{------------------------------------------------------------------------------}

procedure AddWindow2 (wPtr: grafPortPtr);

{ Add a window to the window menu				}
{								}
{ Parameters:							}
{    wPtr - window to add					}


procedure CheckWindow (wp: grafPortPtr);

{ Check a window's menu item, unchecking any old ones           }
{								}
{ Parameters:							}
{    wp - window to check					}


procedure DrawControlWindow;

{ Draw a window with nothing but controls			}


procedure FlagError (error, tError: integer);

{ Flag an error							}
{								}
{ Parameters:							}
{    error - error message number				}
{    tError - toolbox error code; 0 if none			}


procedure FreePString (resourceID: longint);

{ Free a resource string					}
{								}
{ Parameters:							}
{    resourceID - resource ID of the rPString to free		}


function GetPString (resourceID: longint): pStringPtr;

{ Get a string from the resource fork				}
{								}
{ Parameters:							}
{    resourceID - resource ID of the rPString resource		}
{								}
{ Returns: pointer to the string; nil for an error		}
{								}
{ Notes: The string is in a locked resource handle.  The	}
{    caller should call FreePString when the string is no	}
{    longer needed.  Failure to do so is not catastrophic;	}
{    the memory will be deallocated when the program is shut	}
{    down.							}


procedure SetMenuState (state: menuStateType); extern;

{ Highlight menus based on the program state			}
{								}
{ Parameters:							}
{    state - new menu state					}


procedure Null0;

{ Set prefix 0 to null						}


function OSStringsEqual (s1, s2: gsosInStringPtr): boolean;

{ See if two GS/OS strings are equal				}
{								}
{ Parameters:							}
{    s1, s2 - strings to compare				}
{								}
{ Returns: True if the strings are equal, else false		}


function OSStringToPString (str: gsosInStringPtr): pStringPtr;

{ Converts a GS/OS input string to a pString			}
{								}
{ Parameters:							}
{    str - GS/OS input string					}
{								}
{ Returns: Pointer to equivalent p-string			}
{								}
{ Notes: The string is in a fixed buffer which is safe until	}
{    the next call to this subroutine.  It is not dynamically	}
{    allocated, and should not be disposed of.			}


procedure OutOfMemory;

{ flag an out of memory error					}


function PStringToOSString (str: pStringPtr): gsosInStringPtr;

{ Converts a p-string to a GS/OS string				}
{								}
{ Parameters:							}
{    str - p-string						}
{								}
{ Returns: Pointer to equivalent GS/OS string			}
{								}
{ Notes: The string is in a fixed buffer which is safe until	}
{    the next call to this subroutine.  It is not dynamically	}
{    allocated, and should not be disposed of.			}


procedure RemoveWindow (wPtr: grafPortPtr);

{ remove a window from the window menu				}
{								}
{ Parameters:							}
{    wPtr - name of the window to remove 			}


function ToUpper (ch: char): char;

{ Convert characters to uppercase				}
{								}
{ Parameters:							}
{	   ch - character to convert				}
{								}
{ Returns: uppercase of ch 					}


function UserStop: boolean;

{ check for a user-flagged stop (open-apple .)			}
{								}
{ Returns: true if stop flagged, else false			}

{------------------------------------------------------------------------------}

implementation

uses GSOS;

var
   osstr: gsosInString;			{last string converted by PStringtoOSString}
   pstr: pString;			{last string converted by OSStringToPString}
   selectedWindow: integer;		{currently selected window}

{------------------------------------------------------------------------------}

procedure ResetCursor; extern;

{ switch to the arrow cursor					}
{								}
{ Notes: Defined in Buffer.pas					}

{-- Local subroutines ---------------------------------------------------------}

procedure brk; extern;

procedure UpdateWindowList;

{ Recreate and renumber the window list				}

const
   firstMenuWindowNum = 310;		{first item # for window in window menu}
   windowMenu	 = 4;			{window menu #}

var
   count: 0..maxint;			{number of windows processed}
   sp: pStringPtr;			{window title}
   wlp: windowMenuListPtr;		{work pointer}

begin {UpdateWindowList}
wlp := windowMenuList;			{delete the existing menus}
while wlp <> nil do begin
   if wlp^.menuID <> 0 then
      DeleteMItem(wlp^.menuID);
   wlp := wlp^.next;
   end; {while}
wlp := windowMenuList;			{add new items to the list}
count := 0;
while wlp <> nil do begin
   count := count+1;
   wlp^.menuID := count-1+firstMenuWindowNum;
   sp := pointer(GetWTitle(wlp^.wptr));
   wlp^.menuItem := concat('--', sp^, '\N', cnvis(wlp^.menuID), chr(return));
   InsertMItem(@wlp^.menuItem, -1, windowMenu);
   if ToolError <> 0 then
      OutOfMemory;
   if FrontWindow = wlp^.wptr then begin
      selectedWindow := wlp^.menuID;
      CheckMItem(true,wlp^.menuID);
      end; {if}
    wlp := wlp^.next;
   end; {while}
CalcMenuSize(0,0,windowMenu);		{resize the menu}
end; {UpdateWindowList}

{-- Globally available subroutines --------------------------------------------}

procedure AddWindow2 {wPtr: grafPortPtr};

{ Add a window to the window menu				}
{								}
{ Parameters:							}
{    wPtr - window to add					}

var
   wlp: windowMenuListPtr;		{work pointer}

begin {AddWindow2}
new(wlp);
if windowMenuList <> nil then
   windowMenuList^.last := wlp;
wlp^.next := windowMenuList;
wlp^.last := nil;
wlp^.menuID := 0;
wlp^.wPtr := wPtr;
windowMenuList := wlp;
UpdateWindowList;
end; {AddWindow2}


procedure CheckWindow {wp: grafPortPtr};

{ Check a window's menu item, unchecking any old ones           }
{								}
{ Parameters:							}
{    wp - window to check					}

var
   wlp: windowMenuListPtr;		{work pointer}

begin {CheckWindow}
wlp := windowMenuList;
while wlp <> nil do
   if wlp^.wPtr = wp then begin
      CheckMItem(false,selectedWindow);
      selectedWindow := wlp^.menuID;
      CheckMItem(true,selectedWindow);
      wlp := nil;
      end {if}
   else
      wlp := wlp^.next;
end; {CheckWindow}


{$databank+}

procedure DrawControlWindow;

{ Draw a window with nothing but controls			}

begin {DrawControlWindow}
PenNormal;
DrawControls(GetPort);
end; {DrawControlWindow}

{$databank-}


procedure FlagError {error, tError: integer};

{ Flag an error							}
{								}
{ Parameters:							}
{    error - error message number				}
{    tError - toolbox error code; 0 if none			}

const
   errorAlert = 2000;			{alert resource ID}
   errorBase = 2000;			{base resource ID for error messages}

var
   str: pString;			{work string}
   substArray: pStringPtr;		{substitution "array"}
   button: integer;			{button pushed}


   function HexDigit (value: integer): char;

   { Returns a hexadecimal digit for the value			}
   {								}
   { Parameters:						}
   {    value - value to form a digit from; only the least	}
   {       significant 4 bits are used				}
   {								}
   { Returns: Hexadecimal character				}

   begin {HexDigit}
   value := value & $000F;
   if value > 9 then
      HexDigit := chr(value-10 + ord('A'))
   else
      HexDigit := chr(value + ord('0'));
   end; {HexDigit}


begin {FlagError}
					{form the error string}
substArray := GetPString(base + errorBase + error);
str := substArray^;
FreePString(base + errorBase + error);
substArray := @str;
if tError <> 0 then begin		{add the tool error number}
   str := concat(
      str,
      ' ($',
      HexDigit(tError >> 12),
      HexDigit(tError >> 8),
      HexDigit(tError >> 4),
      HexDigit(tError),
      ')'
      );
   end; {if}
ResetCursor;				{show the alert}
if length(str) < 55 then
   button := AlertWindow($0005, @substArray, base+errorAlert)
else if length(str) < 110 then
   button := AlertWindow($0005, @substArray, base+errorAlert+1)
else
   button := AlertWindow($0005, @substArray, base+errorAlert+2);
end; {FlagError}


procedure FreePString {resourceID: longint};

{ Free a resource string					}
{								}
{ Parameters:							}
{    resourceID - resource ID of the rPString to free		}

const
   rPString = $8006;			{resource type for p-strings}

begin {FreePString}               
ReleaseResource(-3, rPString, resourceID);
end; {FreePString}


function GetPString {resourceID: longint): pStringPtr};

{ Get a string from the resource fork				}
{								}
{ Parameters:							}
{    resourceID - resource ID of the rPString resource		}
{								}
{ Returns: pointer to the string; nil for an error		}
{								}
{ Notes: The string is in a locked resource handle.  The	}
{    caller should call FreePString when the string is no	}
{    longer needed.  Failure to do so is not catastrophic;	}
{    the memory will be deallocated when the program is shut	}
{    down.							}

const
   rPString = $8006;                 {resource type for p-strings}

var
   hndl: handle;                     {resource handle}

begin {GetPString}
hndl := LoadResource(rPString, resourceID);
if ToolError <> 0 then
   GetPString := nil
else begin
   HLock(hndl);
   GetPString := pStringPtr(hndl^);
   end; {else}
end; {GetPString}


procedure Null0;

{ Set prefix 0 to null						}

var
   gpRec: getPrefixOSDCB;		{for GetPrefix calls}
        
begin {Null0}
gpRec.pcount := 2;
gpRec.prefix := @gpRec.prefixNum;
gpRec.prefixNum := 0;
SetPrefixGS(gpRec);
end; {Null0}


function OSStringsEqual {s1, s2: gsosInStringPtr): boolean};

{ See if two GS/OS strings are equal				}
{								}
{ Parameters:							}
{    s1, s2 - strings to compare				}
{								}
{ Returns: True if the strings are equal, else false		}

var
   i: unsigned;				{loop/index variable}

begin {OSStringsEqual}
if s1^.size = s2^.size then begin
   OSStringsEqual := true;
   i := s1^.size;
   while i <> 0 do
      if ToUpper(s1^.theString[i]) <> ToUpper(s2^.theString[i]) then begin
         i := 0;
         OSStringsEqual := false;
         end {if}
      else
         i := i-1;
   end {if}
else
   OSStringsEqual := false;
end; {OSStringsEqual}


function OSStringToPString {str: gsosInStringPtr): pStringPtr};

{ Converts a GS/OS input string to a pString			}
{								}
{ Parameters:							}
{    str - GS/OS input string					}
{								}
{ Returns: Pointer to equivalent p-string			}
{								}
{ Notes: The string is in a fixed buffer which is safe until	}
{    the next call to this subroutine.  It is not dynamically	}
{    allocated, and should not be disposed of.			}

var
   i: unsigned;				{loop/index variable}

begin {OSStringToPString}
pstr[0] := chr(str^.size);
for i := 1 to str^.size do
   pstr[i] := str^.theString[i];
OSStringToPString := @pstr;
end; {OSStringToPString}


procedure OutOfMemory;

{ flag an out of memory error					}

begin {OutOfMemory}
FlagError(2, $201);
end; {OutOfMemory}


function PStringToOSString {str: pStringPtr): gsosInStringPtr};

{ Converts a p-string to a GS/OS string				}
{								}
{ Parameters:							}
{    str - p-string						}
{								}
{ Returns: Pointer to equivalent GS/OS string			}
{								}
{ Notes: The string is in a fixed buffer which is safe until	}
{    the next call to this subroutine.  It is not dynamically	}
{    allocated, and should not be disposed of.			}

begin {PStringToOSString}
osstr.size := ord(str^[0]);
osstr.theString := str^;
PStringToOSString := @osstr;
end; {PStringToOSString}


procedure RemoveWindow {wPtr: grafPortPtr};

{ remove a window from the window menu				}
{								}
{ Parameters:							}
{    wPtr - name of the window to remove 			}

var
   wlp: windowMenuListPtr;		{work pointer}

begin {RemoveWindow}
wlp := windowMenuList;
while wlp <> nil do
   if wlp^.wPtr = wPtr then begin
      DeleteMItem(wlp^.menuID);
      if wlp^.last = nil then
	 windowMenuList := wlp^.next
      else
	 wlp^.last^.next := wlp^.next;
      if wlp^.next <> nil then
	 wlp^.next^.last := wlp^.last;
      dispose(wlp);
      wlp := nil;
      UpdateWindowList;
      end {if}
   else
      wlp := wlp^.next;
end; {RemoveWindow}


function ToUpper {ch: char): char};

{ Convert characters to uppercase				}
{								}
{ Parameters:							}
{	   ch - character to convert				}
{								}
{ Returns: uppercase of ch 					}

begin {ToUpper}
if (ch >= 'a') and (ch <= 'z') then
   ch := chr(ord(ch)-ord('a')+ord('A'));
ToUpper := ch;
end; {ToUpper}
   

function UserStop{: boolean};

{ check for a user-flagged stop (open-apple .)			}
{								}
{ Returns: true if stop flagged, else false			}

var
   lastEvent: eventRecord;		{last event returned in event loop}
   event: boolean;			{dummy var for dumping an event}

begin {Stop}
UserStop := false;
event := GetNextEvent($074E,lastEvent);
if lastEvent.eventWhat = keyDownEvt then
   if ord(lastEvent.eventMessage & $7F) = ord('.') then
      UserStop := ord(lastEvent.eventModifiers & $10) <> 0;
end; {Stop}

end.

{$append 'pcommon.asm'}
