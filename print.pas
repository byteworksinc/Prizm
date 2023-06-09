{$optimize 7}
{---------------------------------------------------------------}
{								}
{  This module contains the printing routines.			}
{								}
{  By Mike Westerfield						}
{								}
{  Copyright 1988						}
{  Byte Works, Inc.						}
{								}
{---------------------------------------------------------------}

unit Print;

interface

uses Common, QuickDrawII, EventMgr, WindowMgr, MemoryMgr, DialogMgr, PrintMgr,
   FontMgr;

{$LibPrefix '0/obj/'}

{$segment 'Prism'}

uses PCommon, Buffer;

procedure DoPageSetup;

{ set up the printer page					}


procedure DoPrint;

{ print the current file 					}


procedure InitPrinter;

{ initialize the print module					}

{------------------------------------------------------------------------------}

implementation

var
   pHandle: handle;			{print record handle}


procedure SetPrinterDefaults;

{ Set the normal defaults for good program text			}

const
   laserWriter = 3;			{laserwriter code}

var
   ph: prHandle;			{print record handle}

begin {SetPrinterDefaults}
HLock(pHandle);
ph := prHandle(pHandle);
with ph^^ do begin
   if prInfo.iDev = laserWriter then
      prStl.vSizing := 1;
   end; {with}
HUnlock(pHandle);
end; {SetPrinterDefaults}


procedure DoPageSetup;

{ Set up the printer options					}

var
   changed: boolean;			{did the print record change?}

begin {DoPageSetup}
if pHandle = nil then begin		{make sure there is a print record}
   pHandle := NewHandle(140, userID, 0, nil);
   if pHandle <> nil then begin
      PrDefault(pHandle);
      if ToolError = 0 then
         SetPrinterDefaults
      else begin
         FlagError(26, ToolError);
         DisposeHandle(pHandle);
         pHandle := nil;
         end; {if}
      end {if}
   else
      FlagError(26, ToolError);
   end; {if}
if pHandle <> nil then			{update the print record}
   changed := PrStlDialog(pHandle);
end; {DoPageSetup}


procedure DoPrint;

{ print the current file 					}


   procedure PrintDocument;

   { Do the actual printing of the document			}

   var
      col: 0..maxint;			{column number}
      dispY: 0..maxint;			{vertical displacememtn on the page}
      fontInfo: fontInfoRecord;		{current font info}
      leftmargin, topmargin: 0..maxint;	{margin size}
      startPtr,endPtr: charPtr;		{start, end of area to print}
      status: prStatusRec;		{printer status}
      pageRect: rect;			{printer's page rectangle}
      prPort: grafPortPtr;		{printer's grafPort}


      procedure DoFontStuff;

      { Do setup related to the font				}

      var
         f: fontID;			{printer font}

      begin {DoFontStuff}
      f.famNum := 22;
      f.fontStyle := 0;
      f.fontSize := 7;
      InstallFont(f, 0);
      GetFontInfo(fontInfo);
      leftmargin := fontInfo.widMax*6;
      with fontinfo do
         topmargin := (ascent + descent + leading)*2;
      end; {DoFontStuff}


      procedure GetPageSize (pHand: handle; var r: rect);

      { Get the page size for one printer page			}
      {								}
      { Parameters:						}
      {    pHand - print record handle				}
      {    r: (output) rectangle to fill in			}

      var
         pPtr: prRecPtr;		{pointer to print record}

      begin {GetPageSize}
      HLock(pHand);
      pPtr := pointer(pHand^);
      r := pPtr^.prInfo.rPage;
      HUnlock(pHand);
      end; {GetPageSize}


      procedure GetPrintRange;

      { Get the range of text to print				}

      begin {GetPrintRange}
      Compact;				{Make the buffer contiguous}
      with currentFile do		{determine range to print}
	 if selection then begin
	    if ord4(select) < ord4(cursor) then begin
	       startPtr := select;
	       endPtr := cursor;
	       end {if}
	    else begin
	       startPtr := cursor;
	       endPtr := select;
	       end; {else}
	    end {if}
	 else begin
	    startPtr := buffStart;
	    endPtr := gapStart;
	    end; {else}
      end; {GetPrintRange}


   begin {PrintDocument}
   {main print loop}
   PrSetDocName(@currentFile.fileName);
   prPort := PrOpenDoc(pHandle, nil);
   GetPageSize(pHandle, pageRect);
   if ToolError <> 0 then
      FlagError(26, ToolError)
   else begin
      GetPrintRange;
      DoFontStuff;
      while startPtr <> endPtr do begin
         PrOpenPage(prPort, nil);
         if ToolError <> 0 then begin
            FlagError(27, ToolError);
            startPtr := endPtr;
            end {if}
         else begin
	    dispY := topMargin + fontInfo.leading + fontInfo.ascent;
	    repeat
               MoveTo(leftmargin, dispY);
               col := 0;
               while (startPtr <> endPtr) and (startPtr^ <> RETURN) do begin
        	  if startPtr^ = TAB then
                     repeat
                	DrawChar(' ');
                	col := col+1;
                     until (col > 255) or (currentFile.ruler[col] <> 0)
        	  else begin
                     DrawChar(chr(startPtr^));
                     col := col+1;
                     end; {else}
        	  startPtr := pointer(ord4(startPtr)+1);
        	  end; {while}
               if startPtr <> endPtr then
        	  startPtr := pointer(ord4(startPtr)+1);
               with fontInfo do
        	  dispY := dispY + ascent + descent + leading;
	    until dispy + fontInfo.descent + topmargin > pageRect.v2 - pageRect.v1;
            PrClosePage(prPort);
            end; {else}
         end; {while}
      Expand;
      PrCloseDoc(prPort);
      end; {else}

   {spooling loop}
   if PrError = 0 then
      PrPicFile(pHandle, nil, @status);
   end; {PrintDocument}


begin {DoPrint}
if pHandle = nil then begin		{make sure there is a print record}
   pHandle := NewHandle(140, userID, 0, nil);
   if pHandle <> nil then begin
      PrDefault(pHandle);
      if ToolError = 0 then
         SetPrinterDefaults
      else begin
         FlagError(26, ToolError);
         DisposeHandle(pHandle);
         pHandle := nil;
         end; {if}
      end {if}
   else
      FlagError(26, ToolError);
   end; {if}
if pHandle <> nil then			{print the document}
   if PrJobDialog(pHandle) then
      PrintDocument;
end; {DoPrint}


procedure InitPrinter;

{ initialize the print module					}

begin {InitPrinter}
pHandle := nil;
end; {InitPrinter}

end.
