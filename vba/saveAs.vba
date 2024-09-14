

' Subroutine to select all tables in the active document and add editing permission to everyone.
Sub selecttables()
    ' Declare a variable to hold the current table being processed.
    Dim mytable As Table

    ' Disable screen updates to improve performance.
    Application.ScreenUpdating = False

    ' Loop through all tables in the document.
    For Each mytable In ActiveDocument.Tables
        ' Add editing permission to everyone for the table.
        mytable.Range.Editors.Add wdEditorEveryone
    Next

    ' Select all editable ranges for everyone in the document.
    ActiveDocument.SelectAllEditableRanges (wdEditorEveryone)

    ' Delete all editable ranges for everyone in the document.
    ActiveDocument.DeleteAllEditableRanges (wdEditorEveryone)

    ' Enable screen updates again.
    Application.ScreenUpdating = True
End Sub
