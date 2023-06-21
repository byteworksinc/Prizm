{$optimize 7}
{---------------------------------------------------------------}
{								}
{  This module contains the find and replace procedures.  Also	}
{  lumped in, for lack of a better spot, is Goto.		}
{								}
{  By Mike Westerfield						}
{								}
{  Copyright 1987						}
{  Byte Works, Inc.						}
{								}
{---------------------------------------------------------------}

unit Find;

interface

{$segment 'Prism'}
  
uses Common, QuickDrawII, EventMgr, WindowMgr, DialogMgr, ControlMgr,
     MscToolSet, MenuMgr;

{$LibPrefix '0/obj/'}

uses PCommon, Buffer;

var
   frWPtr: grafPortPtr;			{window for find/replace dialog}

					{check box flag values}
  isWholeWord,isCaseSensitive,isFoldWhiteSpace: boolean;

  findPatt,replacePatt: searchString;	{find, replace strings}


procedure DoFind;

{ Find a string							}


procedure DoGoto;

{ go to a line number						}


procedure DoReplace;

{ replace a string						}


procedure HandleReplaceEvent (event: eventRecord);

{ Handle an event while the replace window is active		}


function ReplaceIBeam (p: point): boolean;

{ Check to see if the cursor should be an I-Beam		}
{								}
{ Parameters:							}
{    p - cursor location (global coordinates)			}
{								}
{ Returns: True for I-Beam, else false				}

{------------------------------------------------------------------------------}

implementation

const
   rplReplaceFind	= 1;		{control IDs for replace window}
   rplCancel		= 2;
   rplTitle1		= 3;
   rplFindPatt		= 4;
   rplWholeWord		= 5;
   rplCase		= 6;
   rplWhite		= 7;
   rplReplaceNext	= 8;
   rplReplaceAll	= 9;
   rplTitle2		= 10;
   rplReplacePatt	= 11;

var
   dEvent: eventRecord;			{last event returned by DoModalWindow}
   frRect: rect; 			{size of the modeless dialog}

{------------------------------------------------------------------------------}

procedure GetLETextByID2 (theWindow: grafPortPtr; controlID: longint;
   var text: searchString); tool ($10, $3B);


procedure CheckMenus;

{ Check the status of the menus					}

begin {CheckMenus}
if length(findPatt) = 0 then begin
   DisableMItem(find_FindSame);
   DisableMItem(find_ReplaceSame);
   end {if}
else begin
   EnableMItem(find_FindSame);
   EnableMItem(find_ReplaceSame);
   end; {else}
end; {CheckMenus}

{------------------------------------------------------------------------------}

procedure DoFind;

{ Find a string							}

const
   resID 	= 4000;			{resource IDs}
   dlgFindNext	= 1;
   dlgCancel	= 2;
   dlgTitle	= 3;
   dlgFindPatt	= 4;
   dlgWholeWord	= 5;
   dlgCase	= 6;
   dlgWhite	= 7;

var
   dlgPtr: grafPortPtr;			{dialog pointer}
   part: integer;			{part code}

begin {DoFind}
if frWPtr <> nil then begin		{if the replace window is open, close it}
   CloseWindow(frWPtr);
   frWPtr := nil;
   end; {if}
					{create the find dialog}
dlgPtr := NewWindow2(nil, 0, @DrawControlWindow, nil, $02, base+resID, rWindParam1);
if dlgPtr <> nil then begin
   SetCtlValueByID(ord(isWholeWord), dlgPtr, dlgWholeWord);
   SetCtlValueByID(ord(isCaseSensitive), dlgPtr, dlgCase);
   SetCtlValueByID(ord(isFoldWhiteSpace), dlgPtr, dlgWhite);
   SetLETextByID(dlgPtr, dlgFindPatt, findPatt);
   ResetCursor;
   repeat
      part := ord(DoModalWindow(dEvent, nil, nil, nil, $C01A));
   until part in [dlgFindNext, dlgCancel];
   ResetCursor;
   if part = dlgFindNext then begin
      isWholeWord := 0 <> GetCtlValueByID(dlgPtr, dlgWholeWord);
      isCaseSensitive := 0 <> GetCtlValueByID(dlgPtr, dlgCase);
      isFoldWhiteSpace := 0 <> GetCtlValueByID(dlgPtr, dlgWhite);
      GetLETextByID2(dlgPtr, dlgFindPatt, findPatt);
      CloseWindow(dlgPtr);
      DrawControls(FrontWindow);
      if length(findPatt) <> 0 then begin
	 WaitCursor;
	 Find(findPatt, isWholeWord, isCaseSensitive, isFoldWhiteSpace, true);
	 ResetCursor;
         end; {if}
      end {if}
   else
      CloseWindow(dlgPtr);
   end; {if}
CheckMenus;				{make sure the proper menus are enabled}
end; {DoFind}


procedure DoGoto;

{ go to a line number						}

const
   resID 	= 6000;			{resource ID}
   gtoGoto	= 1;			{control IDs}
   gtoCancel	= 2;
   gtoTitle	= 3;
   gtoLinePatt	= 4;
   
var
   gtPtr: grafPortPtr;			{dialog box pointer}
   part: integer;			{dialog item hit}
   num: longint; 			{line number}
   numStr: pString;			{number string}

begin {DoGoto}
gtPtr := NewWindow2(nil, 0, @DrawControlWindow, nil, $02, base+resID, rWindParam1);
if gtPtr <> nil then begin
   ResetCursor;
   repeat
      part := ord(DoModalWindow(dEvent, nil, nil, nil, $C01A));
   until part in [gtoGoto, gtoCancel];
   ResetCursor;
   if part = gtoGoto then begin
      GetLETextByID(gtPtr, gtoLinePatt, numStr);
      CloseWindow(gtPtr);
      if length(numStr) <> 0 then begin
	 num := cnvsl(numStr);
	 if num < 1 then num := 1;
	 num := num-1;
	 with currentFile do
	    if num < topLine then
	       ScrollUp(topLine-num)
	    else
	       ScrollDown(num-topLine);
	 Position(0,0);
         end; {if}
      end {if}
   else
      CloseWindow(gtPtr);
   end; {if}
CheckMenus;				{make sure the proper menus are enabled}
end; {DoGoto}


procedure DoReplace;

{ replace a string						}

const
   resID 	= 5000;			{resource ID}

begin {DoReplace}
if frWPtr = nil then begin
   frWPtr :=
      NewWindow2(nil, 0, @DrawControlWindow, nil, $02, base+resID, rWindParam1);
   SetCtlValueByID(ord(isWholeWord), frWPtr, rplWholeWord);
   SetCtlValueByID(ord(isCaseSensitive), frWPtr, rplCase);
   SetCtlValueByID(ord(isFoldWhiteSpace), frWPtr, rplWhite);
   SetLETextByID(frWPtr, rplFindPatt, findPatt);
   SetLETextByID(frWPtr, rplReplacePatt, replacePatt);
   SetLETextByID(frWPtr, rplFindPatt, findPatt);
   MakeThisCtlTarget(GetCtlHandleFromID(frWPtr, rplFindPatt));
   end {if}
else
   SelectWindow(frWPtr);
end; {DoReplace}


procedure HandleReplaceEvent {event: eventRecord};

{ Handle an event while the replace window is active		}


   procedure ReadControls;

   { Read the state of the controls				}

   begin {ReadControls}
   isWholeWord := 0 <> GetCtlValueByID(frWPtr, rplWholeWord);
   isCaseSensitive := 0 <> GetCtlValueByID(frWPtr, rplCase);
   isFoldWhiteSpace := 0 <> GetCtlValueByID(frWPtr, rplWhite);
   GetLETextByID2(frWPtr, rplFindPatt, findPatt);
   GetLETextByID2(frWPtr, rplReplacePatt, replacePatt);
   end; {ReadControls}


   procedure DoCancel;

   { Handle a hit on the Cancel button				}

   begin {DoCancel}
   CloseWindow(frWPtr);
   frWPtr := nil;
   end; {DoCancel}


   procedure DoReplaceAll;

   { Handle a hit on the Replace All button			}

   begin {DoReplaceAll}
   ReadControls;
   if length(findPatt) <> 0 then
      ReplaceAll(findPatt, replacePatt, isWholeWord, isCaseSensitive,
         isFoldWhiteSpace);
   end; {DoReplaceAll}


   procedure DoReplaceFind;

   { Handle a hit on the Replace, then Find button		}

   var
      lDisableScreenUpdates: boolean;	{local copy of disableScreenUpdates}

   begin {DoReplaceFind}
   ReadControls;
   if currentFile.selection then begin
      StartDrawing(currentFile.wPtr);
      DeleteSelection;
      DoPaste(false,pointer(ord4(@replacePatt)+1),ord(replacePatt[0]));
      if length(findPatt) <> 0 then begin
	 lDisableScreenUpdates := disableScreenUpdates;
	 disableScreenUpdates := true;
	 WaitCursor;
	 Find(findPatt,isWholeWord,isCaseSensitive,isFoldWhiteSpace,true);
	 ResetCursor;
	 disableScreenUpdates := lDisableScreenUpdates;
	 DrawScreen;
	 end; {else}
      end; {if}
   end; {DoReplaceFind}


   procedure DoReplaceNext;

   { Handle a hit on the Find Next button			}

   var
      lDisableScreenUpdates: boolean;	{local copy of disableScreenUpdates}

   begin {DoReplaceNext}
   ReadControls;
   if length(findPatt) <> 0 then begin
      lDisableScreenUpdates := disableScreenUpdates;
      disableScreenUpdates := true;
      WaitCursor;
      Find(findPatt, isWholeWord, isCaseSensitive, isFoldWhiteSpace, true);
      ResetCursor;
      disableScreenUpdates := lDisableScreenUpdates;
      DrawScreen;
      end; {else}
   end; {DoReplaceNext}


begin {HandleReplaceEvent}
if (event.taskData4 & $FFFF8000) = 0 then
   case ord(event.taskData4) of
      rplReplaceFind:	DoReplaceFind;
      rplCancel:	DoCancel;
      rplReplaceNext:	DoReplaceNext;
      rplReplaceAll:	DoReplaceAll;
      otherwise:	;
      end; {case}
CheckMenus;
end; {HandleReplaceEvent}


function ReplaceIBeam {p: point): boolean};

{ Check to see if the cursor should be an I-Beam		}
{								}
{ Parameters:							}
{    p - cursor location (global coordinates)			}
{								}
{ Returns: True for I-Beam, else false				}

var
   ctl: ctlRecHndl;			{control handle}
   part: 0..maxint;			{control part code}
   port: grafPortPtr;			{caller's grafPort}

begin {ReplaceIBeam}
port := GetPort;
SetPort(frWPtr);
GlobalToLocal(p);
part := FindCursorCtl(ctl, p.h, p.v, frWPtr);
ReplaceIBeam := false;
if ctl <> nil then
   if ord(GetCtlID(ctl)) in [rplFindPatt,rplReplacePatt] then
      ReplaceIBeam := true;
SetPort(port);
end; {ReplaceIBeam}

end.
