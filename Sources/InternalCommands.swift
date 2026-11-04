import AppKit

extension CommanderController {
    /// Original command spellings supported by the native dispatcher.
    /// Unknown names remain errors, never silently launch a shell command.
    func dispatchInternalCommand(_ raw: String) -> Bool {
        switch raw.lowercased() {
        case "cm_srcshort": briefView()
        case "cm_srclong": fullView()
        case "cm_srctree": treeView()
        case "cm_srcthumbs": thumbnailView()
        case "cm_srcquickview": toggleQuickView()
        case "cm_verticalpanels": verticalArrangement()
        case "cm_config": configuration()
        case "cm_configsavepos": saveWindowPosition()
        case "cm_configsavesettings": saveConfiguration()
        case "cm_srcexecs": showPrograms()
        case "cm_srcallfiles": showAllFiles()
        case "cm_srcuserdef": customFileMask()
        case "cm_srcuserspec": lastFileMask()
        case "cm_srcunsorted": unsortedOrder()
        case "cm_copyfiledetailstoclip": copyDetails(withPaths:false)
        case "cm_copyfpfiledetailstoclip": copyDetails(withPaths:true)
        case "cm_copynamestoclip": NSPasteboard.general.clearContents();NSPasteboard.general.setString(activePane.selectedEntries.map(\.name).joined(separator:"\n"),forType:.string)
        case "cm_saveselectiontofile": saveSelectionFile()
        case "cm_loadselectionfromfile": loadSelectionFile()
        case "cm_ftpdisconnect": disconnectFTP()
        case "cm_srcbyname": sortSource("name")
        case "cm_srcbyext": sortSource("ext")
        case "cm_srcbysize": sortSource("size")
        case "cm_srcbydatetime": sortSource("date")
        case "cm_rereadsource": refreshSource()
        case "cm_list", "cm_listinternalonly", "cm_listonly": viewFile(editable:false)
        case "cm_edit", "cm_editexistingfile": viewFile(editable:true)
        case "cm_editnewfile": newTextFile()
        case "cm_copy", "cm_copyotherpanel": transfer(move:false)
        case "cm_renmov": transfer(move:true)
        case "cm_renamesinglefile": renameCurrent()
        case "cm_mkdir": makeFolder()
        case "cm_delete": trash()
        case "cm_packfiles", "cm_copytoarchive": packFiles()
        case "cm_unpackfiles": unpackFiles()
        case "cm_split": splitFile()
        case "cm_combine": combineFiles()
        case "cm_searchfor": searchFiles()
        case "cm_multirenamefiles": multiRename()
        case "cm_filesync": synchronizeDirectories()
        case "cm_comparedirs": compareFileLists()
        case "cm_comparefilesbycontent": compareFiles()
        case "cm_exchange": swap()
        case "cm_exchangeselection": invertSelection()
        case "cm_selectall": selectAllFiles()
        case "cm_clearall": clearSelection()
        case "cm_opennewtab": newTab()
        case "cm_closecurrenttab": closeTab()
        case "cm_closealltabs": closeAllTabs()
        case "cm_gotopreviousdir": backFolder()
        case "cm_gotonextdir": forwardFolder()
        case "cm_copyfullnamestoclip": copyFullNames()
        case "cm_copytoclipboard": copyFilesToClipboard()
        case "cm_pastefromclipboard": pasteFilesFromClipboard()
        case "cm_crcCreate".lowercased(): createChecksums()
        case "cm_crccheck": verifyChecksums()
        case "cm_ftpconnect", "cm_ftpnew": connectFTP()
        case "cm_quit": exitApp()
        default:
            if let catalog=try? ReferenceMenuCatalog.load(),let definition=catalog.commandsBySymbol[raw.lowercased()] {return routeReferenceCommand(definition.id)}
            return false
        }
        return true
    }
}
