#!/usr/bin/swift

// Swift Typing Tutor v2.4
// Final Implementation: July 2, 2025
// - Replaces the modal exercise editor sheet with a separate, resizable window.
// - Allows for in-place, non-modal editing of new and existing exercises.

import SwiftUI
import Charts
import UniformTypeIdentifiers
import Combine

// MARK: - 1. DATA MODELS
struct Exercise: Codable, Identifiable, Hashable { var id: UUID, name: String, text: String }
struct HistoryEntry: Codable, Identifiable, Hashable { var id: UUID, exerciseId: UUID, exerciseName: String, exerciseLength: Int, completionDate: Date, charactersPerMinute: Int, wordsPerMinute: Int, errorPercentage: Double, totalErrors: Int, topMistakes: [String: Int] }
struct Theme: Codable, Identifiable, Hashable { var id: UUID, name: String, fontName: String = "Menlo", fontSize: Double = 22.0, backgroundColor: CodableColor = .init(hex: "#002b36"), defaultTextColor: CodableColor = .init(hex: "#839496"), correctTextColor: CodableColor = .init(hex: "#2aa198"), incorrectTextColor: CodableColor = .init(hex: "#dc322f"), cursorColor: CodableColor = .init(hex: "#586e75"), specialCharColor: CodableColor = .init(hex: "#cb4b16") }
struct AppConfiguration: Codable { var lastUsedThemeId: UUID, themes: [Theme] }
struct CodableColor: Codable, Hashable {
    var red: Double, green: Double, blue: Double, opacity: Double
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity) }
    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: opacity) }
    init(color: Color) { let c = NSColor(color); self.red=c.redComponent; self.green=c.greenComponent; self.blue=c.blueComponent; self.opacity=c.alphaComponent }
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: .alphanumerics.inverted); var int: UInt64 = 0; Scanner(string: hex).scanHexInt64(&int)
        let a,r,g,b: UInt64
        switch hex.count {
        case 3: (a,r,g,b) = (255, (int>>8)*17, (int>>4&0xF)*17, (int&0xF)*17); case 6: (a,r,g,b) = (255, int>>16, int>>8&0xFF, int&0xFF); case 8: (a,r,g,b) = (int>>24, int>>16&0xFF, int>>8&0xFF, int&0xFF); default:(a,r,g,b) = (255,0,0,0)
        }
        self.red=Double(r)/255; self.green=Double(g)/255; self.blue=Double(b)/255; self.opacity=Double(a)/255
    }
}

// MARK: - 2. STORAGE SERVICE
struct StorageService {
    let rootUrl: URL
    init() { do { let d = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true); self.rootUrl = d.appendingPathComponent("SwiftTypeTutor"); try FileManager.default.createDirectory(at: exercisesUrl, withIntermediateDirectories: true); try FileManager.default.createDirectory(at: historyUrl, withIntermediateDirectories: true) } catch { fatalError("E: \(error)") } }
    var configUrl: URL { rootUrl.appendingPathComponent("config.json") }
    var exercisesUrl: URL { rootUrl.appendingPathComponent("exercises") }
    var historyUrl: URL { rootUrl.appendingPathComponent("history") }
    func loadConfiguration() -> AppConfiguration {
        if let data = try? Data(contentsOf: configUrl), let config = try? JSONDecoder().decode(AppConfiguration.self, from: data) { return config }
        let t1 = Theme(id: UUID(), name: "Solarized Dark"), t2 = Theme(id: UUID(), name: "Classic Light", fontName: "Helvetica", fontSize: 20, backgroundColor: .init(hex: "#FFFFFF"), defaultTextColor: .init(hex: "#000000"), correctTextColor: .init(hex: "#008000"), incorrectTextColor: .init(hex: "#FF0000"), cursorColor: .init(hex: "#D3D3D3"), specialCharColor: .init(hex: "#0000FF"))
        let config = AppConfiguration(lastUsedThemeId: t1.id, themes: [t1, t2]); saveConfiguration(config)
        if (try? FileManager.default.contentsOfDirectory(at: exercisesUrl, includingPropertiesForKeys: nil))?.isEmpty ?? true { saveExercise(Exercise(id: UUID(), name: "Pangram", text: "The quick brown fox jumps over the lazy dog.")) }
        return config
    }
    func saveConfiguration(_ config: AppConfiguration) { let e=JSONEncoder(); e.outputFormatting = .prettyPrinted; do{try e.encode(config).write(to: configUrl, options: .atomic)}catch{print("E: \(error)")} }
    func loadExercises() -> [Exercise] { guard let urls = try? FileManager.default.contentsOfDirectory(at: exercisesUrl, includingPropertiesForKeys: nil) else { return [] }; return urls.compactMap { u in if u.pathExtension=="json", let d=try? Data(contentsOf:u){return try? JSONDecoder().decode(Exercise.self,from:d)}; return nil } }
    func saveExercise(_ e: Exercise) { let enc=JSONEncoder(); enc.outputFormatting = .prettyPrinted; do{try enc.encode(e).write(to: exercisesUrl.appendingPathComponent("\(e.id.uuidString).json"), options: .atomic)}catch{print("E: \(error)")} }
    func deleteExercise(_ e: Exercise) { try? FileManager.default.removeItem(at: exercisesUrl.appendingPathComponent("\(e.id.uuidString).json")) }
    func loadHistory() -> [HistoryEntry] { guard let urls = try? FileManager.default.contentsOfDirectory(at: historyUrl, includingPropertiesForKeys: nil) else { return [] }; let d=JSONDecoder(); d.dateDecodingStrategy = .iso8601; return urls.compactMap { u in if u.pathExtension=="json", let data=try? Data(contentsOf:u){return try? d.decode(HistoryEntry.self,from:data)}; return nil } }
    func saveHistoryEntry(_ h: HistoryEntry) { let e=JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = .prettyPrinted; do{try e.encode(h).write(to: historyUrl.appendingPathComponent("\(h.id.uuidString).json"),options: .atomic)}catch{print("E: \(error)")} }
}

// MARK: - 3. APP STATE
@MainActor
class AppState: ObservableObject {
    @Published var configuration: AppConfiguration; @Published var exercises: [Exercise]; @Published var history: [HistoryEntry]
    private let storage: StorageService
    init() { self.storage=StorageService(); self.configuration=storage.loadConfiguration(); self.exercises=storage.loadExercises(); self.history=storage.loadHistory() }
    var currentTheme: Theme { configuration.themes.first { $0.id == configuration.lastUsedThemeId } ?? configuration.themes.first! }
    func saveConfig() { storage.saveConfiguration(configuration); objectWillChange.send() }
    func addExercise(_ e: Exercise) { exercises.append(e); storage.saveExercise(e) }
    func updateExercise(_ e: Exercise) { if let i = exercises.firstIndex(where: {$0.id==e.id}) { exercises[i]=e; storage.saveExercise(e) } }
    func deleteExercise(_ e: Exercise) { exercises.removeAll{$0.id==e.id}; storage.deleteExercise(e) }
    func addHistoryEntry(_ h: HistoryEntry) { history.append(h); storage.saveHistoryEntry(h) }
    
    // NEW: State for managing editor windows, moved here from MainView
    var editorWindows: [UUID: NSWindow] = [:]
    var editorCancellables: [UUID: AnyCancellable] = [:]
}

// MARK: - 4. UI VIEWS

struct MainView: View {
    @EnvironmentObject var appState: AppState
    @State private var sheetContent: SheetContent? = nil
    @State private var exerciseToRename: Exercise? = nil

    enum SheetContent: Identifiable {
        case settings, progress
        var id: Self { self }
    }
    
    var body: some View {
        NavigationStack {
            List($appState.exercises) { $e in
                NavigationLink(value: e) { ExerciseRowView(exercise: e) }
                .contextMenu {
                    // MODIFIED: Call the new window function
                    Button("Edit") { openExerciseEditor(for: e) }
                    Button("Rename") { exerciseToRename = e }
                    Button("Delete", role: .destructive) { appState.deleteExercise(e) }
                }
            }
            .popover(item: $exerciseToRename) { exercise in
                RenameView(exercise: exercise)
            }
            .navigationTitle("Typing Exercises").navigationDestination(for: Exercise.self) { e in ExerciseView(exercise: e) }
            .toolbar { ToolbarItemGroup(placement: .primaryAction) {
                Button(action: importFromFile) { Label("Import", systemImage: "square.and.arrow.down") }
                // MODIFIED: Call the new window function for a new exercise
                Button(action: { openExerciseEditor(for: nil) }) { Label("Add", systemImage: "plus") }
                Button(action: { sheetContent = .settings }) { Label("Settings", systemImage: "gear") }
                Button(action: { sheetContent = .progress }) { Label("Progress", systemImage: "chart.bar.xaxis") }
            }}
        }
        // REMOVED: .sheet(item: $exerciseToEdit) { ... }
        .sheet(item: $sheetContent) { content in
            switch content {
            case .settings: SettingsView(appState: appState)
            case .progress: ProgressView()
            }
        }
        .preferredColorScheme(appState.currentTheme.backgroundColor.color.isDark() ? .dark : .light)
    }

    // NEW: Function to open the editor in a new window
    private func openExerciseEditor(for exercise: Exercise?) {
        let exerciseToEdit = exercise ?? Exercise(id: UUID(), name: "", text: "")
        
        // If a window for this exercise is already open, bring it to the front
        if let window = appState.editorWindows[exerciseToEdit.id] {
            window.makeKeyAndOrderFront(nil)
            return
        }

        // Create the editor view. It now manages its own state, fixing the crash.
        let editorView = ExerciseEditorView(exercise: exerciseToEdit)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 450),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.center()
        window.title = exercise == nil ? "New Exercise" : "Edit: \(exerciseToEdit.name)"
        
        // Add a hosting view with the editor
        window.contentView = NSHostingView(rootView: editorView.environmentObject(appState))
        
        // Keep track of the window
        appState.editorWindows[exerciseToEdit.id] = window
        
        // NEW: Proper handling of window close notification
        let cancellable = NotificationCenter.default.publisher(for: NSWindow.willCloseNotification, object: window)
            .sink { [weak appState, weak window] _ in // Capture window weakly
                guard let strongWindow = window else { return } // Ensure window still exists
                strongWindow.contentView = nil // Explicitly nil out contentView

                // It's important that exerciseToEdit.id is captured correctly here.
                // This ID was from the moment openExerciseEditor was called.
                appState?.editorWindows.removeValue(forKey: exerciseToEdit.id)
                appState?.editorCancellables.removeValue(forKey: exerciseToEdit.id)
            }
        appState.editorCancellables[exerciseToEdit.id] = cancellable
        
        window.makeKeyAndOrderFront(nil)
    }
    
    private func importFromFile() {
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = false
        if #available(macOS 11.0, *) { panel.allowedContentTypes = [UTType.plainText] }
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                let name = url.deletingPathExtension().lastPathComponent
                // MODIFIED: Open in the new editor window
                openExerciseEditor(for: Exercise(id: UUID(), name: name, text: content))
            } catch { print("Error reading file: \(error)") }
        }
    }
}

struct ExerciseRowView: View {
    let exercise: Exercise
    @EnvironmentObject var appState: AppState
    var body: some View { HStack {
        Image(systemName:"text.book.closed").font(.title).foregroundColor(appState.currentTheme.correctTextColor.color)
        VStack(alignment: .leading) { Text(exercise.name).font(.headline); Text(exercise.text).font(.caption).foregroundColor(.secondary).lineLimit(1) }
    }.padding(.vertical, 4) }
}

struct ExerciseEditorView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss // Still useful if view is ever in a sheet again
    @Environment(\.controlActiveState) var controlActiveState // To find the window
    
    @State private var exercise: Exercise
    private let isNew: Bool
    // NEW: A separate state for the text editor to avoid potential binding issues.
    @State private var bufferedText: String

    init(exercise: Exercise) {
        _exercise = State(initialValue: exercise)
        // Initialize the buffer with the exercise's text
        _bufferedText = State(initialValue: exercise.text)
        // Determine if it's new by checking if it exists in the appState
        let appState = (NSApplication.shared.delegate as! AppDelegate).appState
        self.isNew = !appState.exercises.contains(where: { $0.id == exercise.id })
    }

    private func closeWindow() {
        // Find the window this view is in and close it
        if let window = appState.editorWindows[exercise.id] {
           window.close()
        }
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(isNew ? "Add New Exercise" : "Edit Exercise").font(.largeTitle).padding([.top, .leading, .trailing])
            Form {
                TextField("Exercise Name", text: $exercise.name)
                // MODIFIED: Bind to the buffered text state
                TextEditor(text: $bufferedText).font(.custom("Menlo", size: 14)).frame(minHeight: 300, maxHeight: .infinity).border(Color.secondary.opacity(0.5))
                Button("Import Text from File...") { importText() }
            }.padding()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { closeWindow() }
                Button("Save") {
                    // MODIFIED: Update the exercise text from the buffer before saving
                    exercise.text = bufferedText.normalizingApostrophes()
                    if isNew {
                        appState.addExercise(exercise)
                    } else {
                        appState.updateExercise(exercise)
                    }
                    closeWindow()
                // MODIFIED: The disabled check now uses the buffered text and trims whitespace
                }.disabled(exercise.name.trimmingCharacters(in: .whitespaces).isEmpty || bufferedText.isEmpty)
            }.padding([.bottom, .leading, .trailing])
        }.frame(minWidth: 600, minHeight: 450)
         .onChange(of: controlActiveState) { newState in
            // A trick to update the window title when the name changes
            if let window = appState.editorWindows[exercise.id] {
                window.title = isNew ? "New Exercise" : "Edit: \(exercise.name)"
            }
         }
    }
    
    private func importText() {
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = false
        if #available(macOS 11.0, *) { panel.allowedContentTypes = [UTType.plainText] }
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                self.bufferedText = content // MODIFIED: Update the buffer
                if self.exercise.name.isEmpty { self.exercise.name = url.deletingPathExtension().lastPathComponent }
            } catch { print("Error reading file: \(error)") }
        }
    }
}

// ... (Rest of the file remains the same)

struct RenameView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @FocusState private var isFocused: Bool
    
    let exercise: Exercise
    @State private var newName: String = ""

    init(exercise: Exercise) {
        self.exercise = exercise
        _newName = State(initialValue: exercise.name)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Rename Exercise").font(.headline)
            TextField("New Name", text: $newName)
                .focused($isFocused)
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") {
                    var updatedExercise = exercise; updatedExercise.name = newName.trimmingCharacters(in: .whitespaces); appState.updateExercise(updatedExercise); dismiss()
                }.disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || newName == exercise.name)
            }
        }.padding().frame(width: 300).onAppear { isFocused = true }
    }
}

struct KeyCaptureView: NSViewRepresentable {
    var onKeyPress: (String) -> Void
    func makeNSView(context: Context) -> NSKeyCaptureView { let v = NSKeyCaptureView(); v.onKeyPress = onKeyPress; return v }
    func updateNSView(_ nsView: NSKeyCaptureView, context: Context) {}
}
class NSKeyCaptureView: NSView {
    var onKeyPress: ((String) -> Void)?; override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); self.window?.makeFirstResponder(self) }
    override func keyDown(with event: NSEvent) { guard let chars = event.characters else { return }; onKeyPress?(chars) }
}

struct ExerciseView: View {
    @EnvironmentObject var appState: AppState; @Environment(\.dismiss) var dismiss
    let exercise: Exercise; var textChars: [Character] { Array(exercise.text) }
    @State private var typedText: [Character?] = []
    @State private var currentIndex: Int = 0
    @State private var errorCount: Int = 0
    @State private var startTime: Date? = nil
    @State private var currentTime = Date()
    @State private var mistakeLog: [String: Int] = [:]
    @State private var isFinished = false
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var body: some View {
        VStack(spacing: 20) {
            StatsHeaderView(totalChars:textChars.count, errors:errorCount, typedChars:typedText.compactMap{$0}.count, startTime:startTime, currentTime:currentTime)
            TypingAreaView(textChars: textChars, typedText: typedText, currentIndex: currentIndex)
            if isFinished { CompletionFooterView() }
        }
        .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(appState.currentTheme.backgroundColor.color.ignoresSafeArea())
        .background(KeyCaptureView { input in handleInput(input) })
        .onAppear {
            typedText = Array(repeating: nil, count: textChars.count)
            mistakeLog = [:]
        }
        .onReceive(timer) { newTime in guard !isFinished else { return }; if startTime != nil { currentTime = newTime } }
    }
    private func handleInput(_ input: String) {
        guard !isFinished, let typedChar = input.first else { return }; if startTime == nil { startTime = Date() }
        let correctChar = textChars[currentIndex]; var isMatch = (typedChar == correctChar)
        if correctChar.isNewline && (typedChar == "\r" || typedChar == "\n") { isMatch = true }
        if isMatch {
            typedText[currentIndex] = correctChar; if currentIndex < textChars.count-1 { currentIndex += 1 } else { finishExercise() }
        } else {
            if typedText[currentIndex] == nil {
                errorCount += 1
                let key = correctChar.isNewline ? "⏎" : String(correctChar)
                mistakeLog[key, default: 0] += 1
            }; typedText[currentIndex] = typedChar
        }
    }
    private func finishExercise() {
        isFinished = true; let finalTime = Date(), elapsed = finalTime.timeIntervalSince(startTime!); let cpm = Int(Double(textChars.count)/elapsed*60), wpm = cpm/5
        let errPercent = Double(errorCount)/Double(textChars.count)*100; self.currentTime = finalTime
        let h=HistoryEntry(id:UUID(), exerciseId:exercise.id, exerciseName:exercise.name, exerciseLength:textChars.count, completionDate:finalTime, charactersPerMinute:cpm, wordsPerMinute:wpm, errorPercentage:errPercent, totalErrors:errorCount, topMistakes:mistakeLog)
        appState.addHistoryEntry(h)
    }
}

struct StatsHeaderView: View {
    let totalChars:Int, errors:Int, typedChars:Int, startTime:Date?, currentTime:Date
    var body: some View { HStack {
        statBox(title:"Total", value:"\(totalChars)"); statBox(title:"Errors", value:"\(errors)")
        statBox(title:"Error %", value:String(format:"%.1f",errorPercentage)); statBox(title:"CPM", value:"\(cpm)")
        statBox(title:"WPM", value: String(cpm/5))
    }}
    private var errorPercentage: Double { typedChars > 0 ? Double(errors)/Double(typedChars)*100 : 0.0 }
    private var cpm: Int { guard let start = startTime, typedChars > 0 else { return 0 }; let elapsed = currentTime.timeIntervalSince(start); guard elapsed > 1 else { return 0 }; let correctChars = typedChars - errors; return Int(Double(correctChars)/elapsed*60) }
    private func statBox(title:String, value:String) -> some View { VStack { Text(title).font(.caption).foregroundColor(.secondary); Text(value).font(.title2).fontWeight(.semibold) }.frame(minWidth: 70) }
}

struct TypingAreaView: View {
    @EnvironmentObject var appState: AppState; let textChars: [Character], typedText: [Character?], currentIndex: Int
    var body: some View { ScrollView { Text(buildAttributedString()).padding().frame(maxWidth:.infinity, alignment:.leading).lineSpacing(appState.currentTheme.fontSize * 0.75) }.background(appState.currentTheme.backgroundColor.color.opacity(0.5)).cornerRadius(8) }
    private func buildAttributedString() -> AttributedString {
        var finalString = AttributedString(); let theme = appState.currentTheme
        for i in 0..<textChars.count {
            let char = textChars[i]; var displayChar = String(char); var container = AttributeContainer()
            container.font = .custom(theme.fontName, size: theme.fontSize)
            if char.isNewline { displayChar = "⏎\n" }; if char == "\t" { displayChar = "→" }; if char.isNewline || char == "\t" { container.foregroundColor = theme.specialCharColor.nsColor }
            var styledChar = AttributedString(displayChar, attributes: container)
            if i < typedText.count, let typedChar = typedText[i] {
                var color = typedChar == char ? theme.correctTextColor.nsColor : theme.incorrectTextColor.nsColor
                if char.isNewline && (typedChar == "\r" || typedChar == "\n") { color = theme.correctTextColor.nsColor }
                styledChar.foregroundColor = color
            } else { if !char.isNewline && char != "\t" { styledChar.foregroundColor = theme.defaultTextColor.nsColor } }
            if i == currentIndex { styledChar.backgroundColor = theme.cursorColor.nsColor }
            finalString.append(styledChar)
        }
        return finalString
    }
}

struct CompletionFooterView: View { @Environment(\.dismiss) var dismiss; var body: some View { VStack { Text("Complete!").font(.largeTitle).foregroundColor(.green); Text("Results saved to History.").padding(.bottom); Button("Back to Exercises"){dismiss()} }}}

struct SettingsView: View {
    @EnvironmentObject var appState: AppState; @Environment(\.dismiss) var dismiss
    @State private var selectedThemeId: UUID; @State private var currentConfig: AppConfiguration
    @State private var fontSearchText: String = ""
    
    private var availableFonts: [String] { NSFontManager.shared.availableFontFamilies.sorted() }
    private var filteredFonts: [String] {
        if fontSearchText.isEmpty { return availableFonts }
        return availableFonts.filter { $0.localizedCaseInsensitiveContains(fontSearchText) }
    }
    
    init(appState: AppState) { _selectedThemeId = State(initialValue:appState.configuration.lastUsedThemeId); _currentConfig = State(initialValue:appState.configuration) }
    var selectedProxy: Binding<Theme> { Binding<Theme>( get: { self.currentConfig.themes.first{$0.id==self.selectedThemeId} ?? self.currentConfig.themes.first! }, set: { newTheme in if let i=self.currentConfig.themes.firstIndex(where:{$0.id==self.selectedThemeId}) { self.currentConfig.themes[i]=newTheme } } )}
    
    var body: some View {
        VStack {
            Text("Settings").font(.largeTitle).padding()
            HSplitView { themeList.frame(minWidth: 150, maxWidth: 250); themeEditor.frame(maxWidth: .infinity) }
            HStack { Button("Cancel", role: .cancel) { dismiss() }; Button("Save") { appState.configuration = currentConfig; appState.configuration.lastUsedThemeId = selectedThemeId; appState.saveConfig(); dismiss() } }.padding()
        }.frame(minWidth: 700, minHeight: 550)
    }
    
    var themeList: some View { VStack { List(currentConfig.themes, selection:$selectedThemeId){t in Text(t.name).tag(t.id)}; HStack{Button(action:add){Image(systemName:"plus")}; Button(action:delete){Image(systemName:"minus")}.disabled(currentConfig.themes.count<=1)}.padding(.bottom,8) }}
    
    var themeEditor: some View { Form {
        TextField("Name", text: selectedProxy.name)
        Picker("Font Family", selection: selectedProxy.fontName) {
            ForEach(filteredFonts, id: \.self) { fontName in
                Text(fontName).font(.custom(fontName, size: 14))
            }
        }
        .searchable(text: $fontSearchText, prompt: "Search fonts")
        Stepper("Font Size: \(Int(selectedProxy.fontSize.wrappedValue))", value: selectedProxy.fontSize, in: 10...40)
        Divider().padding(.vertical)
        ColorPicker("BG",selection:Binding(get:{selectedProxy.backgroundColor.wrappedValue.color},set:{selectedProxy.backgroundColor.wrappedValue = .init(color:$0)}))
        ColorPicker("Text",selection:Binding(get:{selectedProxy.defaultTextColor.wrappedValue.color},set:{selectedProxy.defaultTextColor.wrappedValue = .init(color:$0)}))
        ColorPicker("Correct",selection:Binding(get:{selectedProxy.correctTextColor.wrappedValue.color},set:{selectedProxy.correctTextColor.wrappedValue = .init(color:$0)}))
        ColorPicker("Incorrect",selection:Binding(get:{selectedProxy.incorrectTextColor.wrappedValue.color},set:{selectedProxy.incorrectTextColor.wrappedValue = .init(color:$0)}))
        ColorPicker("Cursor",selection:Binding(get:{selectedProxy.cursorColor.wrappedValue.color},set:{selectedProxy.cursorColor.wrappedValue = .init(color:$0)}))
        ColorPicker("Special Chars",selection:Binding(get:{selectedProxy.specialCharColor.wrappedValue.color},set:{selectedProxy.specialCharColor.wrappedValue = .init(color:$0)}))
    }.padding() }
    
    private func add() { let t=Theme(id:UUID(),name:"New Theme"); currentConfig.themes.append(t); selectedThemeId=t.id }
    private func delete() { if let i=currentConfig.themes.firstIndex(where:{$0.id==selectedThemeId}) { let delId=currentConfig.themes[i].id; currentConfig.themes.remove(at:i); if selectedThemeId==delId {selectedThemeId=currentConfig.themes.first!.id} }}
}

struct ProgressView: View {
    @EnvironmentObject var appState: AppState; @Environment(\.dismiss) var dismiss
    private var history: [HistoryEntry] { appState.history.sorted{$0.completionDate < $1.completionDate} }
    var body: some View { VStack { Text("Progress").font(.largeTitle).padding(); if history.isEmpty { Spacer(); Text("No history yet.").font(.title2); Spacer() } else {
        Chart(history){e in LineMark(x:.value("Date",e.completionDate,unit:.day), y:.value("CPM",e.charactersPerMinute)).foregroundStyle(by:.value("Metric","CPM")); LineMark(x:.value("Date",e.completionDate,unit:.day), y:.value("Error %",e.errorPercentage)).foregroundStyle(by:.value("Metric","Error %")) }.chartForegroundStyleScale(["CPM":.blue, "Error %":.red]).padding()
        List(history.reversed()) { e in
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(e.exerciseName).font(.headline)
                    Text(e.completionDate.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                    if !e.topMistakes.isEmpty {
                        let sortedMistakes = e.topMistakes.sorted { $0.value > $1.value }.prefix(3)
                        HStack(spacing: 8) {
                            Text("Mistakes:").font(.headline)
                            ForEach(Array(sortedMistakes), id: \.key) { mistake in
                                Text("'\(mistake.key)' (\(mistake.value))").font(.headline).padding(.horizontal, 5).padding(.vertical, 2).foregroundColor(appState.currentTheme.incorrectTextColor.color).background(Color.secondary.opacity(0.15)).cornerRadius(4)
                            }
                        }.padding(.top, 2)
                    }
                }
                Spacer()
                VStack(alignment: .trailing) { Text("CPM: \(e.charactersPerMinute)").font(.callout).monospacedDigit(); Text("Err: \(String(format:"%.1f", e.errorPercentage))%").font(.callout).monospacedDigit() }
            }
        }
    }; HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }.padding() }.frame(minWidth:800, minHeight:600) }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor let appState = AppState()
    var window: NSWindow!
    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.regular)
        let view = MainView().environmentObject(appState)
        window = NSWindow(contentRect:NSRect(x:0,y:0,width:800,height:600), styleMask:[.titled,.closable,.miniaturizable,.resizable], backing:.buffered, defer:false)
        window.center(); window.setFrameAutosaveName("MainAppWindow")
        window.contentView = NSHostingView(rootView: view); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationWillTerminate(_ n: Notification) { appState.saveConfig() }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { return true }
}
extension Color {
    func isDark() -> Bool {
        let c = NSColor(self); guard let comps = c.cgColor.components, comps.count >= 3 else { var w:CGFloat=0; c.getWhite(&w,alpha:nil); return w < 0.5 }
        return (0.2126*comps[0] + 0.7152*comps[1] + 0.0722*comps[2]) < 0.5
    }
}

extension String {
    func normalizingApostrophes() -> String {
        let replacements = [
            "’": "'", "‘": "'", "´": "'", "`": "'"
        ]
        return replacements.reduce(self) { $0.replacingOccurrences(of: $1.key, with: $1.value) }
    }
}
let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.run()