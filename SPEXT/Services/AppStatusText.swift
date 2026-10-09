enum AppStatusText {
    static let pasteBlocked = "Einfügen blockiert"
    static let hotkeysBlocked = "Hotkeys blockiert"

    static let pasteBlockedExplanation = """
    SPEXT hat den Text in die Zwischenablage kopiert, darf aber ohne Bedienungshilfen-Zugriff kein ⌘V auslösen. Eingabeüberwachung reicht dafür nicht aus. Erlaube SPEXT in Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen oder drücke einmal manuell ⌘V.
    """

    static let pasteTargetChangedExplanation = """
    SPEXT hat den Text in die Zwischenablage kopiert, aber nicht automatisch eingefügt. Das Zielfenster oder die Zwischenablage hat sich während der Verarbeitung geändert, oder der Bedienungshilfen-Zugriff fehlt. Wechsle zum gewünschten Feld und drücke ⌘V.
    """

    static let hotkeysBlockedExplanation = """
    SPEXT darf keine globalen Tastaturbefehle überwachen. Erlaube SPEXT in Systemeinstellungen → Datenschutz & Sicherheit → Eingabeüberwachung. Bedienungshilfen allein reicht dafür nicht aus.
    """
}
