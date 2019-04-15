{
  This is a modified version of the "Worldspace move references into another worldspace.pas"
  script, that is included with TES4Edit. Modifications include copying and overriding of
  landscape, pathgrid and region data.



  Move selected temporary references into another worldspace with provided offset values
  Optionally copy and move persistent references that belong to the selected cells by coordinates
  "only this plugin" option controls which persistent references to move
    - unchecked: refs in master file will be processed, copied as override into this plugin and then moved
    - checked: only already copied refs in this plugin will be moved
  Optionally updated teleport coordinates on doors leading to the moved markers
  
  The plugin that the script is applied to must be the last one loaded in xEdit
  Supports all games (Oblivion, Fallout 3, New Vegas, Skyrim, Fallout 4)
  
  Usage:
  Copy as override temporary cells/refs you want to move (optionally copy persistent refs), apply script to them, set parameters
  After script finished working, don't browse any nodes but immediately exit xEdit and save changes, then reload and check results
}
unit MoveWorldspaceRefs;

const
  sRefSignatures = 'REFR,ACHR,ACRE,PGRE,PMIS,PHZD,PARW,PBAR,PBEA,PCON,PFLA';

var
  DestWorld, SrcPCell, DestPCell, PRefs: IInterface;
  fOffsetX, fOffsetY, fOffsetZ: Double;
  bMovePersistent, bPersistentThisFileOnly, bInitSource, bUpdateDoors: Boolean;
  frm: TForm;
  lbl: TLabel;
  cmbWorldspace: TComboBox;
  edX, edY, edZ: TEdit;
  chkPersistent, chkThisFile, chkDoors: TCheckBox;
  btnOk, btnCancel: TButton;
  
//============================================================================
// get cell record by X,Y grid coordinates from worldspace
function GetCellFromWorldspace(Worldspace: IInterface; GridX, GridY: integer): IInterface;
var
  blockidx, subblockidx, cellidx: integer;
  wrldgrup, block, subblock, cell: IInterface;
  Grid, GridBlock, GridSubBlock: TwbGridCell;
  LabelBlock, LabelSubBlock: Cardinal;
begin
  Grid := wbGridCell(GridX, GridY);
  GridSubBlock := wbSubBlockFromGridCell(Grid);
  LabelSubBlock := wbGridCellToGroupLabel(GridSubBlock);
  GridBlock := wbBlockFromSubBlock(GridSubBlock);
  LabelBlock := wbGridCellToGroupLabel(GridBlock);

  wrldgrup := ChildGroup(Worldspace);
  // iterate over Exterior Blocks
  for blockidx := 0 to Pred(ElementCount(wrldgrup)) do begin
    block := ElementByIndex(wrldgrup, blockidx);
    if GroupLabel(block) <> LabelBlock then Continue;
    // iterate over SubBlocks
    for subblockidx := 0 to Pred(ElementCount(block)) do begin
      subblock := ElementByIndex(block, subblockidx);
      if GroupLabel(subblock) <> LabelSubBlock then Continue;
      // iterate over Cells
      for cellidx := 0 to Pred(ElementCount(subblock)) do begin
        cell := ElementByIndex(subblock, cellidx);
        if (Signature(cell) <> 'CELL') or GetIsPersistent(cell) then Continue;
        if (GetElementNativeValues(cell, 'XCLC\X') = GridX) and (GetElementNativeValues(cell, 'XCLC\Y') = GridY) then begin
          Result := cell;
          Exit;
        end;
      end;
      Break;
    end;
    Break;
  end;
end;

//============================================================================
// get persistent cell record from worldspace
function GetPersistentCellFromWorldspace(Worldspace: IInterface): IInterface;
var
  i: integer;
  worldspaceFormID: Cardinal;
begin
  worldspaceFormID := GetLoadOrderFormId(Worldspace);
  if worldspaceFormID = 0 then begin
    addmessage('ERROR: GetPersitentCellFromWorldspace() invalid worldspace.');
	Result := nil;
	Exit;
  end;

  for i := 0 to ElementCount(ChildGroup(Worldspace)) do begin
    Result := ElementByIndex(ChildGroup(Worldspace), i);
	if Signature(Result) = 'CELL' then
	  break;
  end;
  if Signature(Result) <> 'CELL' then begin
    addmessage( Format('ERROR: could not find persistent cell for worldspace [%s]', [IntToHex(worldspaceFormID,8)]) );
	Result := nil;
  end;

end;

//===========================================================================
function IsReference(aRecord: IInterface): Boolean;
begin
  Result := Pos(Signature(aRecord), sRefSignatures) <> 0;
end;

//===========================================================================
procedure UpdateRefPosition(aRef: IInterface; aPath: string);
var
  x, y, z: Single;
begin
  // calculate and update new position
  x := GetElementNativeValues(aRef, aPath + 'X') + fOffsetX;
  y := GetElementNativeValues(aRef, aPath + 'Y') + fOffsetY;
  z := GetElementNativeValues(aRef, aPath + 'Z') + fOffsetZ;
  SetElementNativeValues(aRef, aPath + 'X', x);
  SetElementNativeValues(aRef, aPath + 'Y', y);
  SetElementNativeValues(aRef, aPath + 'Z', z);
end;

//===========================================================================
procedure MoveReference(aRef: IInterface);
var
  cell, overrideWorld: IInterface;
  c: TwbGridCell;
  x,y: Single;
  pos: TwbVector;
  overrideIndex, numOverrides: integer;
begin

  if GetIsVisibleWhenDistant(aRef) then begin
    SetIsVisibleWhenDistant(aRef, False);
  end;

  // find destination cell coordinates
  x: = GetElementNativeValues(aRef, 'DATA\Position\X') + fOffsetX;
  y := GetElementNativeValues(aRef, 'DATA\Position\Y') + fOffsetY;
  pos.x := x;
  pos.y := y;
  c := wbPositionToGridCell(pos);

  // get cell from the current plugin
  numOverrides := OverrideCount(DestWorld);
//  addmessage(Format('DEBUG: MoveRef() - DestWorld[%s][%s] - has numOverrides=[%d], WinningOverride=[%s]', [Name(DestWorld), IntToHex(GetLoadOrderFormID(DestWorld),8), numOverrides, GetFileName(GetFile(WinningOverride(DestWorld)))]));
  overrideIndex := numOverrides;
  cell := GetCellFromWorldspace(WinningOverride(DestWorld), c.X, c.Y);
  // if not found, try next highest override
  if not Assigned(cell) then begin
    while (overrideIndex > 0 and not Assigned(cell)) do begin
	    overrideIndex := overrideIndex - 1;
	    overrideWorld := OverrideByIndex(DestWorld, overrideIndex);
//      addmessage(Format('DEBUG: MoveRef() - Searching DestWorld in [%d]th Override = [%s]', [overrideIndex, GetFileName(GetFile(overrideWorld))]));
      cell := GetCellFromWorldspace(overrideWorld, c.X, c.Y);
    end;
  end;
  if not Assigned(cell) then begin
    cell := GetCellFromWorldspace(Master(DestWorld), c.X, c.Y);
    if not Assigned(cell) then begin
      addmessage( Format('can not find destination cell [%d,%d] for reference record: [%s]', [c.X, c.Y, IntToHex(GetLoadOrderFormID(aRef),8)]) );
      //raise Exception.Create('Can not find destination cell ' + IntToStr(c.X) + ',' + IntToStr(c.Y));
      exit;
    end;
  end;

  UpdateRefPosition(aRef, 'DATA\Position\');

  // if cell is not in our plugin yet, then copy as override
  if not Equals(GetFile(cell), GetFile(aRef)) then begin
    AddRequiredElementMasters(cell, GetFile(aRef), False);
    cell := wbCopyElementToFile(cell, GetFile(aRef), False, True);
  end;
  
  // move reference
  SetElementEditValues(aRef, 'Cell', Name(cell));
end;

//============================================================================
procedure chkPersistentClick(Sender: TObject);
begin
  chkThisFile.Enabled := TCheckBox(Sender).Checked;
  chkDoors.Enabled := TCheckBox(Sender).Checked;
end;

//===========================================================================
function Initialize: integer;
var
  sl: TStringList;
  i, j: integer;
  wrlds, wrld: IInterface;
begin
  frm := TForm.Create(nil);
  try
    frm.Caption := 'Move references';
    frm.Width := 400;
    frm.Height := 200;
    frm.Position := poMainFormCenter;
    frm.BorderStyle := bsDialog;

    lbl := TLabel.Create(frm); lbl.Parent := frm;
    lbl.Left := 12;
    lbl.Top := 12;
    lbl.Width := 100;
    lbl.Caption := 'Destination worldspace';
    
    cmbWorldspace := TComboBox.Create(frm); cmbWorldspace.Parent := frm;
    cmbWorldspace.Left := 12;
    cmbWorldspace.Top := 28;
    cmbWorldspace.Width := frm.Width - 36;
    cmbWorldspace.Style := csDropDownList; cmbWorldspace.DropDownCount := 20;

    sl := TStringList.Create;
    try
      sl.Duplicates := dupIgnore;
      sl.Sorted := True;
      for i := Pred(FileCount) downto 0 do begin
        wrlds := GroupBySignature(FileByIndex(i), 'WRLD');
        for j := 0 to Pred(ElementCount(wrlds)) do begin
          wrld := ElementByIndex(wrlds, j);
          if Signature(wrld) = 'WRLD' then
            sl.AddObject(EditorID(wrld), MasterOrSelf(wrld));
        end;
      end;
      cmbWorldspace.Items.Assign(sl);
    finally
      sl.Free;
    end;

    chkPersistent := TCheckBox.Create(frm); chkPersistent.Parent := frm;
    chkPersistent.Left := 12; chkPersistent.Top := 54;
    chkPersistent.Width := 150;
    chkPersistent.Caption := 'Move persistent references';
    chkPersistent.OnClick := chkPersistentClick;
    
    chkThisFile := TCheckBox.Create(frm); chkThisFile.Parent := frm;
    chkThisFile.Left := 170; chkThisFile.Top := 54;
    chkThisFile.Width := 156;
    chkThisFile.Caption := 'only from the current plugin';
    chkThisFile.Hint := 'Persistent references won''t be copied from the master file of source worldspace, but only existing ones in this plugin will be moved';
    chkThisFile.ShowHint := True;
    chkThisFile.Enabled := False;

    chkDoors := TCheckBox.Create(frm); chkDoors.Parent := frm;
    chkDoors.Left := 170; chkDoors.Top := 70;
    chkDoors.Width := 156;
    chkDoors.Caption := 'update doors teleport data';
    chkDoors.Hint := 'If the moved persistent reference is a door and destination door ref links to it, then offset teleport data';
    chkDoors.ShowHint := True;
    chkDoors.Enabled := False;

    chkPersistent.Checked := True;
    chkThisFile.Checked := True;
    chkDoors.Checked := True;

    lbl := TLabel.Create(frm); lbl.Parent := frm;
    lbl.Left := 12; lbl.Top := 82;
    lbl.Width := 100;
    lbl.Caption := 'Offset X,Y,Z';
    
    edX := TEdit.Create(frm); edX.Parent := frm;
    edX.Left := 12; edX.Top := 98; edX.Width := 80;
    edX.Text := '331776';
    edY := TEdit.Create(frm); edY.Parent := frm;
    edY.Left := edX.Left + 100; edY.Top := 98; edY.Width := 80;
    edY.Text := '262144';
    edZ := TEdit.Create(frm); edZ.Parent := frm;
    edZ.Left := edY.Left + 100; edZ.Top := 98; edZ.Width := 80;
    edZ.Text := '0';

    btnOk := TButton.Create(frm); btnOk.Parent := frm;
    btnOk.Caption := 'OK';
    btnOk.ModalResult := mrOk;
    btnOk.Left := frm.Width - 176;
    btnOk.Top := frm.Height - 62;
    btnOk.TabOrder := 0;
    
    btnCancel := TButton.Create(frm); btnCancel.Parent := frm;
    btnCancel.Caption := 'Cancel';
    btnCancel.ModalResult := mrCancel;
    btnCancel.Left := btnOk.Left + btnOk.Width + 8;
    btnCancel.Top := btnOk.Top;

    if (frm.ShowModal <> mrOk) or (cmbWorldspace.ItemIndex = -1) then begin
      Result := 1;
      Exit;
    end;

    DestWorld := ObjectToElement(cmbWorldspace.Items.Objects[cmbWorldspace.ItemIndex]);
    bMovePersistent := chkPersistent.Checked;
    bPersistentThisFileOnly := chkThisFile.Checked;
    bUpdateDoors := chkDoors.Checked;
    if edX.Text = '' then edX.Text := '0'; fOffsetX := FloatToStr(edX.Text);
    if edY.Text = '' then edY.Text := '0'; fOffsetY := FloatToStr(edY.Text);
    if edZ.Text = '' then edZ.Text := '0'; fOffsetZ := FloatToStr(edZ.Text);
    
  finally
    frm.Free;
  end;

  // initialize globals
  bInitSource := False;

end;

//===========================================================================
function Process(e: IInterface): integer;
var
  i, cellx, celly, boolVal, overrideIndex: integer;
  c: TwbGridCell;
  w, ref, doorref, refWorld, destcell, overrideWorld, overrideRecord, regionList, regionID, regionRecord, srcLand, destLand, srcPathgrid, destPathgrid, pointList, point, regionArea: IInterface;
  epos, refpos: TwbVector;
  waterlevel: Double;
  x,y,z: float;
  bResult: boolean;
begin
  //boolVal := bMovePersistent;
  //addmessage(Format('DEBUG: Processing [%s] - bMovePersistent=[%d]', [IntToHex(GetLoadOrderFormID(e),8), boolVal]) );

  if GetIsDeleted(e) or not IsEditable(e) then begin
    addmessage('RECORD is deleted or not editable!');
    Exit;
  end;
  
  if IsReference(e) then begin
    w := LinksTo(ElementByName(e, 'Worldspace'));
    if GetLoadOrderFormID(w) = GetLoadOrderFOrmID(DestWorld) then begin
      Exit;
    end;

    //addmessage('DEBUG: RECORD is a reference...');
    if not GetIsPersistent(e) then begin
      //addmessage('DEBUG: RECORD is a not persistent...'); 
      MoveReference(e);
      exit;
    end;

  end;

  // moving persistent refs for exterior persistent cell
  if GetIsPersistent(e) and (Signature(e) = 'CELL') and bMovePersistent then begin

    //addmessage('DEBUG: RECORD is a persistent...');
    //addmessage(Format('DEBUG: Processing persistent ref: [%s]', [IntToHex(GetLoadOrderFormID(e),8)]) );
    // get persistent cell of source worldspace and it's persistent child group
    if not bInitSource then begin
      addmessage('DEBUG: Initializing PersistentRef List.');
      w := LinksTo(ElementByName(e, 'Worldspace'));
      // what persistent refs to scan - in this plugin or in master file of worldspace
      if not bPersistentThisFileOnly then
      w := MasterOrSelf(w);
      SrcPCell := GetPersistentCellFromWorldspace(w);

    if Assigned(SrcPCell) then
        PRefs := FindChildGroup(ChildGroup(SrcPCell), 8, SrcPCell);
        
    if not Assigned(PRefs) then begin
        addmessage('INITIALIZATION ERROR: No Persistent REFs found.');
      end
      else begin
        addmessage('DEBUG: INITIALIZATION: Persistent REFs found.');
      end;
      bInitSource := True;
    end; // if not bInitSource...

    // nothing to move
    if not Assigned(PRefs) then begin
      addmessage('No Persistent REFs found.');
      Exit;
    end;

    cellx := GetElementNativeValues(e, 'XCLC\X');
    celly := GetElementNativeValues(e, 'XCLC\Y');

    // iterate over all persistent refs of worldspace and check if they belong to the current cell by coordinates
    // in reverse order since elements count might change
    for i := Pred(ElementCount(PRefs)) downto 0 do begin
      ref := WinningOverride(ElementByIndex(PRefs, i));
        
      refWorld := LinksTo(ElementByName(ref, 'Worldspace'));
      if GetLoadOrderFormID(refWorld) = GetLoadOrderFormID(DestWorld) then begin
        Continue;
      end;
        
      // if destination persistent cell is unknown, then locate it first
      if not Assigned(DestPCell) then begin
        DestPCell := WinningOverride(GetPersistentCellFromWorldspace(DestWorld));
        if not Assigned(DestPCell) then
          raise Exception.Create('Can not find destination persistent cell for worldspace ' + Name(DestWorld));
            
        // if destination persistent cell is not in our plugin yet, then copy it as override
        if not Equals(GetFile(DestPCell), GetFile(e)) then begin
          AddRequiredElementMasters(DestPCell, GetFile(e), False);
          DestPCell := wbCopyElementToFile(DestPCell, GetFile(e), False, True);
        end;
      end; // if not Assigned(DestPCell)...
        
      // if persistent ref is not in our plugin, then copy it as override
      if not Equals(GetFile(ref), GetFile(e)) then begin
        AddRequiredElementMasters(ref, GetFile(e), False);
        ref := wbCopyElementToFile(ref, GetFile(e), False, True);
      end;

      // calculate and update new position
      UpdateRefPosition(ref, 'DATA\Position\');

      // move persistent reference
      SetElementEditValues(ref, 'Cell', Name(DestPCell));
      
      // update teleport coordinates leading to the moved persistent ref
      if bUpdateDoors and ElementExists(ref, 'XTEL') then begin
        // getting the door reference
        doorref := WinningOverride(LinksTo(ElementByPath(ref, 'XTEL\Door')));
        // no valid door ref or no teleport data, then skip
        if not Assigned(doorref) then Continue;
        if not ElementExists(doorref, 'XTEL') then Continue;
        // copy it to plugin and update teleport position
        if not Equals(GetFile(doorref), GetFile(e)) then begin
          AddRequiredElementMasters(doorref, GetFile(e), False);
          doorref := wbCopyElementToFile(doorref, GetFile(e), False, True);
          UpdateRefPosition(doorref, 'XTEL\Position/Rotation\Position\');
        end; 
      end; // if bUdpateDoors...
        
    end;  // for i := Pred(ElementCount(PRefs))

  end;  // if GetIsPersistent(e) and (Signature(e) = 'CELL')....

  if (Signature(e) = 'CELL') and (not GetIsPersistent(e)) then begin
    //addmessage('DEBUG: process CELL record...');
	// translate to Target Worldspace... ((gridx * 4096) + foffsetx )/4096
    cellx := GetElementNativeValues(e, 'XCLC\X');
    celly := GetElementNativeValues(e, 'XCLC\Y');
    epos.x := (cellx * 4096) + 2048;
    epos.y := (celly * 4096) + 2048;
    epos.x := epos.x + fOffsetX;
    epos.y := epos.y + fOffsetY;
    c := wbPositionToGridCell(epos);

    // check to see if cell has any children, if not then skip
    if not Assigned(ChildGroup(e)) then begin
//      addmessage('DEBUG: No child groups, skipping cell...');
      exit;
    end;
//    addmessage(Format('DEBUG: analyzing cell[%s][%d,%d], num child groups=[%d]',[IntToHex(GetLoadOrderFormID(e),8), cellx, celly, ElementCount(ChildGroup(e))]));
    // absolute minimum: must have landscape record before processing
    srcLand := GetLandscapeForCell(e);
    if not Assigned(srcLand) then begin
//      addmessage(Format('DEBUG: cell[%s][%d,%d] does not contain landscape record, skipping...',[IntToHex(GetLoadOrderFormID(e),8), cellx, celly]));
      exit;
    end;

    w := LinksTo(ElementByName(e, 'Worldspace'));
    destcell := GetCellFromWorldspace(WinningOverride(DestWorld), c.X, c.Y);
    // if not found, try next highest override
    if not Assigned(destcell) then begin
      overrideIndex := OverrideCount(DestWorld);
      while (overrideIndex > 0 and not Assigned(destcell)) do begin
	      overrideIndex := overrideIndex - 1;
	      overrideWorld := OverrideByIndex(DestWorld, overrideIndex);
        destcell := GetCellFromWorldspace(overrideWorld, c.X, c.Y);
      end;
    end;
    if not Assigned(destcell) then begin
      destcell := GetCellFromWorldspace(DestWorld, c.X, c.Y);
      if not Assigned(destcell) then begin
        addmessage( Format('can not find destination cell [%d,%d] for record: [%s] @ [%d,%d]', [c.X, c.Y, IntToHex(GetLoadOrderFormID(e),8), cellx, celly]) );
        //raise Exception.Create('Can not find destination destcell ' + IntToStr(c.X) + ',' + IntToStr(c.Y));
        exit;
      end;
    end;
    // if cell is not in our plugin yet, then copy as override
    if not Equals(GetFile(destcell), GetFile(e)) then begin
      AddRequiredElementMasters(destcell, GetFile(e), False);
      destcell := wbCopyElementToFile(destcell, GetFile(e), False, True);
    end;

	// over-ride CELL name & EditorID
    SetElementNativeValues(destcell, 'EDID', GetElementNativeValues(e, 'EDID'));
    SetElementNativeValues(destcell, 'FULL', GetElementNativeValues(e, 'FULL'));

  // copy regions (XCLR)
    if ElementExists(e, 'XCLR') then begin
      if not ElementExists(destcell, 'XCLR') then begin
  //      addmessage('DEBUG: inserting blank element...');
        SetElementEditValues(destcell, 'XCLR', '' );
      end;
      ElementAssign(ElementBySignature(destcell, 'XCLR'), LowInteger, ElementBySignature(e, 'XCLR'), False);
      // update regions
      for i := 0 to Pred(ElementCount(ElementBySignature(destcell, 'XCLR'))) do begin
        regionRecord := ElementByIndex( ElementBySignature(destcell, 'XCLR'), i);
        regionRecord := RecordByFormID(GetFile(w), GetNativeValue(regionRecord), True);
//        addmessage(Format('DEBUG: regionRecord[%s] - %s',[GetEditValue(regionRecord), GetNativeValue(regionRecord)]));
        if not UpdateRegionRecord(regionRecord, e) then begin
//          addmessage(Format('ERROR: region[%d] - [%s] not updated',[i, GetEditValue(regionRecord)]));
        end;
      end;
    end;

	// Decrease (XCLW) waterlevel by Z+1
    waterlevel := GetElementNativeValues(e, 'XCLW');
    waterlevel := waterlevel + (fOffsetZ-1);
    SetElementNativeValues(destcell, 'XCLW', waterlevel);

  // copy landscape textures, heights, etc.
//    srcLand := GetLandscapeForCell(e);
    if Assigned(srcLand) then begin
      destLand := GetLandscapeForCell(destcell);
      if not Assigned(destLand) then begin
//        addmessage('DEBUG: could not find destLand, checking overrides');
        overrideIndex := OverrideCount(destcell);
        while (overrideIndex > 0 and not Assigned(destLand)) do begin
	        overrideIndex := overrideIndex - 1;
	        overrideRecord := OverrideByIndex(destcell, overrideIndex);
          destLand := GetLandscapeForCell(overrideRecord);
        end;
      end;
      if not Assigned(destLand) then begin
//        addmessage('DEBUG: destLand still not found, checking destcell Master');
        overrideRecord := Master(destcell);
        destLand := GetLandscapeForCell(overrideRecord);
      end;
      if not Assigned(destLand) then begin
        addmessage(Format('ERROR: destLand not found in destcell Master [%s][%d,%d]', [IntToHex(GetLoadOrderFormID(destcell),8), c.X, c.Y]));
        // create new land record
      end
      else begin
//        addmessage('DEBUG: destLand found in destcell Master');
      end;
      if not Equals(GetFile(destLand), GetFile(e)) then begin
//        addmessage('DEBUG: copying override for destLand');
        AddRequiredElementMasters(destLand, GetFile(e), False);
        destLand := wbCopyElementToFile(destLand, GetFile(e), False, True);
      end;

      ElementAssign(ElementBySignature(destLand, 'DATA'), LowInteger, ElementBySignature(srcLand, 'DATA'), False);
      ElementAssign(ElementBySignature(destLand, 'VNML'), LowInteger, ElementBySignature(srcLand, 'VNML'), False);
      ElementAssign(ElementBySignature(destLand, 'VHGT'), LowInteger, ElementBySignature(srcLand, 'VHGT'), False);

      if ElementExists(srcLand, 'VCLR') then begin
        bResult := ElementExists(destLand, 'VCLR');
        boolVal := bResult;
  //      addmessage(Format('DEBUG: ElementExists(destLand, VCLR) = %d', [boolVal]));
        if not bResult then begin
          SetElementEditValues(destLand, 'VCLR', '');
        end;
        ElementAssign(ElementBySignature(destLand, 'VCLR'), LowInteger, ElementBySignature(srcLand, 'VCLR'), False);
      end;

      if ElementExists(srcLand, 'Layers') then begin
        bResult := ElementExists(destLand, 'Layers');
        boolVal := bResult;
  //      addmessage(Format('DEBUG: ElementExists(destLand, Layers) = %d', [boolVal]));
        if not bResult then begin
          SetElementEditValues(destLand, 'BTXT', '');
        end;
        ElementAssign(ElementByName(destLand, 'Layers'), LowInteger, ElementByName(srcLand, 'Layers'), False);
      end;

    end;

	// copy pathgrids --> translate pathgrid points (PGRP)
    srcPathgrid := GetPathgridForCell(e);
    if Assigned(srcPathgrid) then begin
      destPathgrid := GetPathgridForCell(destcell);
      if not Assigned(destPathgrid) then begin
        overrideIndex := OverrideCount(destcell);
        while (overrideIndex > 0 and not Assigned(destPathgrid)) do begin
	        overrideIndex := overrideIndex - 1;
	        overrideRecord := OverrideByIndex(destcell, overrideIndex);
          destPathgrid := GetPathgridForCell(overrideRecord);
        end;
      end;
      if not Assigned(destPathgrid) then begin
        overrideRecord := Master(destcell);
        destPathgrid := GetPathgridForCell(overrideRecord);
      end;
      if not Assigned(destPathgrid) then begin
//        addmessage('DEBUG: destPathgrid not found in destcell Master');
        destPathgrid := srcPathgrid;
      end;
      if not Equals(GetFile(destPathgrid), GetFile(e)) then begin
//        addmessage('DEBUG: copying override for destLand');
        AddRequiredElementMasters(destPathgrid, GetFile(e), False);
        destLand := wbCopyElementToFile(destPathgrid, GetFile(e), False, True);
      end;
      SetElementEditValues(destPathgrid, 'CELL', Name(destCell));
      pointList := ElementBySignature(destPathgrid, 'PGRP');
//      addmessage(Format('DEBUG: numpoints=[%d]', [ElementCount(pointList)]));
      for i := 0 to ElementCount(pointList)-1 do begin
        point := ElementByIndex(pointList, i);
//        addmessage(Format('DEBUG: point[%d]: numElements=[%d]', [i, ElementCount(point)]));
        refpos.x := GetNativeValue(ElementByIndex(point, 0)) + fOffsetX;
        refpos.y := GetNativeValue(ElementByIndex(point, 1)) + fOffsetY;
        if (fOffsetZ Mod 2) <> 0 then begin
          refpos.z := GetNativeValue(ElementByIndex(point, 2)) + fOffsetZ + 1;
        end
        else begin
          refpos.z := GetNativeValue(ElementByIndex(point, 2)) + fOffsetZ;
        end;
//        addmessage(Format('DEBUG: point[%d] = (%f, %f, %f)', [i, refpos.x, refpos.y, refpos.z]));

        SetNativeValue(ElementByIndex(point,0), refpos.x);
        SetNativeValue(ElementByIndex(point,1), refpos.y);
        SetNativeValue(ElementByIndex(point,2), refpos.z);

      end;
    end;
  end; // if (Signature(e) = 'CELL')....

end;

function UpdateRegionRecord(regionRecord, e: IInterface): boolean;
var
  wnam, recordWorld, regionAreaList, regionArea, regionPoint: IInterface;
  x, y: Double;
  i, j: integer;
begin

  if (Signature(regionRecord) <> 'REGN') then begin
    addmessage('ERROR: record is not a REGN');
    Result := False;
    exit;
  end;

  // set new worldspace
  wnam := ElementBySignature(regionRecord, 'WNAM');
//  addmessage(Format('DEBUG: wnam=[%s], destworld=[%s]', [IntToHex(GetNativeValue(wnam),8), IntToHex(GetLoadOrderFormID(DestWorld),8)]));
  if GetNativeValue(wnam) = GetLoadOrderFormID(DestWorld) then begin
//    addmessage('DEBUG: region is already in DestWorld, skipping');
    Result := False;
    exit;
  end;

  // Make an override copy in current File
  if not Equals(GetFile(regionRecord), GetFile(e)) then begin
    AddRequiredElementMasters(regionRecord, GetFile(e), False);
    regionRecord := wbCopyElementToFile(regionRecord, GetFile(e), False, True);
  end;

  SetElementEditValues(regionRecord, 'WNAM', Name(DestWorld));

//  addmessage(Format('DEBUG: Analyzing Region[%s] - Wrld=[%s], NumRegionAreas=[%d]', [IntToHex(GetLoadOrderFormID(regionRecord),8), GetElementEditValues(regionRecord,'WNAM'), ElementCount(ElementByName(regionRecord, 'Region Areas'))]));
  for i := 0 to Pred(ElementCount(ElementByName(regionRecord, 'Region Areas'))) do begin
    regionArea := ElementByIndex(ElementByName(regionRecord, 'Region Areas'), i);
//    addmessage(Format('DEBUG: Analyzing RegionArea[%d] - NumPoints[%d]', [i, ElementCount(ElementBySignature(regionArea,'RPLD'))]));
    for j := 0 to Pred(ElementCount(ElementBySignature(regionArea, 'RPLD'))) do begin
      regionPoint := ElementByIndex(ElementBySignature(regionArea,'RPLD'), j);
      x := GetNativeValue(ElementByName(regionPoint,'X'));
      y := GetNativeValue(ElementByName(regionPoint,'Y'));
//      addmessage(Format('DEBUG: Analyzing regionPoint[%d] - X=[%f], Y=[%f]', [j, x, y]));
      SetNativeValue(ElementByName(regionPoint,'X'), x + fOffsetX);
      SetNativeValue(ElementByName(regionPoint,'Y'), y + fOffsetY);
    end;
  end;
  // for each region area, udpate pos

  Result := True;

end;

function GetPathgridForCell(cell: IInterface): IInterface;
var
  cellchild, r: IInterface;
  i: integer;
begin
  cellchild := FindChildGroup(ChildGroup(cell), 9, cell); // get Temporary group of cell
  for i := 0 to Pred(ElementCount(cellchild)) do begin
    r := ElementByIndex(cellchild, i);
    if Signature(r) = 'PGRD' then begin
      Result := r;
      Exit;
    end;
  end;
end;

//===========================================================================
// returns LAND record for CELL record
function GetLandscapeForCell(cell: IInterface): IInterface;
var
  cellchild, r: IInterface;
  i: integer;
begin
  cellchild := FindChildGroup(ChildGroup(cell), 9, cell); // get Temporary group of cell
  for i := 0 to Pred(ElementCount(cellchild)) do begin
    r := ElementByIndex(cellchild, i);
    if Signature(r) = 'LAND' then begin
      Result := r;
      Exit;
    end;
  end;
end;


end.
