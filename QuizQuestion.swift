// Format pliku CSV:
// pytanie,odp1,odp2,odp3,odp4,poprawne
// np.: "Stolica Polski?","Kraków","Warszawa","Gdańsk","Łódź","2"
// lub z kilkoma poprawnymi: "Co to jest owoc?","Jabłko","Marchew","Gruszka","Ziemniak","1,3"

import SwiftUI
import SwiftCSV
import UniformTypeIdentifiers
import Combine

// MARK: - Models

struct QuizQuestion: Identifiable, Codable {
    let id: UUID
    let question: String
    let answers: [String]
    let correctIndices: [Int]   // 0-based, Codable nie lubi Set<Int> bez adaptera

    init(question: String, answers: [String], correctIndices: Set<Int>) {
        self.id = UUID()
        self.question = question
        self.answers = answers
        self.correctIndices = Array(correctIndices)
    }
}

struct QuizSet: Identifiable, Codable {
    let id: UUID
    var name: String
    var questions: [QuizQuestion]
    var addedDate: Date

    init(name: String, questions: [QuizQuestion]) {
        self.id = UUID()
        self.name = name
        self.questions = questions
        self.addedDate = Date()
    }
}

// MARK: - Store (persystencja w UserDefaults)

class QuizStore: ObservableObject {
    @Published var sets: [QuizSet] = []

    private let key = "quiz_sets_v1"

    init() { load() }

    func add(_ set: QuizSet) {
        sets.append(set)
        save()
    }

    func delete(at offsets: IndexSet) {
        sets.remove(atOffsets: offsets)
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(sets) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([QuizSet].self, from: data) else { return }
        sets = decoded
    }
}

// MARK: - CSV Parser

func parseCSV(url: URL) throws -> [QuizQuestion] {
    let csv = try CSV<Enumerated>(url: url, encoding: .utf8, loadColumns: false)
    var parsed: [QuizQuestion] = []

    let headerKeywords: Set<String> = ["poprawne", "correct", "answer", "odpowiedź", "indeks"]

    for row in csv.rows {
        guard row.count >= 6 else { continue }

        // Ostatnia kolumna = indeks poprawnych odpowiedzi
        let correctRaw = row.last!.trimmingCharacters(in: .whitespaces)
        let correctLower = correctRaw.lowercased()

        // Pomiń wiersz nagłówkowy
        if headerKeywords.contains(correctLower) { continue }

        let question = row[0].trimmingCharacters(in: .whitespaces)

        // Kolumny środkowe (między pytaniem a indeksem) mogą być rozbite przez
        // przecinki wewnątrz tekstu odpowiedzi (brak cudzysłowów w pliku).
        // Fragmenty zaczynające się od spacji to kontynuacja poprzedniej odpowiedzi.
        let middleCols = Array(row[1..<(row.count - 1)])
        var answers: [String] = []
        var current = ""
        for part in middleCols {
            if part.hasPrefix(" ") && !current.isEmpty {
                // Kontynuacja — przecinek był częścią tekstu odpowiedzi
                current += "," + part
            } else {
                if !current.isEmpty { answers.append(current) }
                current = part
            }
        }
        if !current.isEmpty { answers.append(current) }

        // Musimy mieć dokładnie 4 odpowiedzi
        guard answers.count == 4 else { continue }
        let trimmedAnswers = answers.map { $0.trimmingCharacters(in: .whitespaces) }

        let correctIndices: Set<Int> = Set(
            correctRaw.split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                .map { $0 - 1 }
                .filter { $0 >= 0 && $0 < 4 }
        )

        guard !question.isEmpty, !correctIndices.isEmpty else { continue }
        parsed.append(QuizQuestion(question: question, answers: trimmedAnswers, correctIndices: correctIndices))
    }
    return parsed
}

// MARK: - Quiz Session ViewModel

class QuizSessionViewModel: ObservableObject {
    let quizSet: QuizSet

    @Published var currentQuestion: QuizQuestion? = nil
    @Published var shuffledAnswers: [(text: String, originalIndex: Int)] = []
    @Published var showAnswer: Bool = false

    init(quizSet: QuizSet) {
        self.quizSet = quizSet
    }

    func drawQuestion() {
        guard !quizSet.questions.isEmpty else { return }
        let q = quizSet.questions.randomElement()!
        let indexed = q.answers.enumerated().map { (text: $0.element, originalIndex: $0.offset) }
        shuffledAnswers = indexed.shuffled()
        currentQuestion = q
        showAnswer = false
    }

    func toggleAnswer() {
        showAnswer.toggle()
    }

    func isCorrect(shuffledIndex: Int) -> Bool {
        guard let q = currentQuestion else { return false }
        return q.correctIndices.contains(shuffledAnswers[shuffledIndex].originalIndex)
    }
}

// MARK: - App Entry Point

@main
struct QuizLearningApp: App {
    @StateObject private var store = QuizStore()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(store)
        }
    }
}

// MARK: - Home View

struct HomeView: View {
    @EnvironmentObject var store: QuizStore
    @State private var showAddSheet = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                if store.sets.isEmpty {
                    HomeEmptyState()
                } else {
                    List {
                        ForEach(store.sets) { set in
                            NavigationLink(destination: QuizView(vm: QuizSessionViewModel(quizSet: set))) {
                                SetRow(set: set)
                            }
                        }
                        .onDelete { store.delete(at: $0) }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Zestawy pytań")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddSetSheet()
                    .environmentObject(store)
            }
        }
    }
}

// MARK: - Set Row

struct SetRow: View {
    let set: QuizSet

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "doc.text.fill")
                    .foregroundStyle(Color.accentColor)
                    .font(.system(size: 20))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(set.name)
                    .font(.headline)
                Text("\(set.questions.count) pytań · dodano \(set.addedDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Home Empty State

struct HomeEmptyState: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
            Text("Brak zestawów")
                .font(.title3.bold())
            Text("Naciśnij + aby dodać pierwszy zestaw pytań.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}

// MARK: - Add Set Sheet

struct AddSetSheet: View {
    @EnvironmentObject var store: QuizStore
    @Environment(\.dismiss) var dismiss

    @State private var name: String = ""
    @State private var showFilePicker = false
    @State private var pickedURL: URL? = nil
    @State private var parsedQuestions: [QuizQuestion] = []
    @State private var errorMessage: String? = nil
    @State private var isLoading = false

    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !parsedQuestions.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                // Nazwa zestawu
                Section {
                    TextField("np. Anatomia – kolokwium 1", text: $name)
                } header: {
                    Text("Nazwa zestawu")
                }

                // Wybór pliku
                Section {
                    Button {
                        showFilePicker = true
                    } label: {
                        HStack {
                            Image(systemName: "folder.badge.plus")
                                .foregroundStyle(Color.accentColor)
                            Text(pickedURL == nil ? "Wybierz plik CSV…" : pickedURL!.lastPathComponent)
                                .foregroundStyle(pickedURL == nil ? .secondary : .primary)
                            Spacer()
                            if isLoading {
                                ProgressView()
                            }
                        }
                    }

                    if let err = errorMessage {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    if !parsedQuestions.isEmpty {
                        Label("\(parsedQuestions.count) pytań wczytanych pomyślnie", systemImage: "checkmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.green)
                    }
                } header: {
                    Text("Plik z pytaniami")
                } footer: {
                    Text("Format: pytanie,odp1,odp2,odp3,odp4,indeks(y)\nIndeksy od 1, kilka poprawnych: np. \"1,3\"")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Nowy zestaw")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Dodaj") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        store.add(QuizSet(name: trimmed, questions: parsedQuestions))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.commaSeparatedText, .plainText],
                allowsMultipleSelection: false
            ) { result in
                handleFilePick(result)
            }
        }
    }

    private func handleFilePick(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            pickedURL = url
            errorMessage = nil
            parsedQuestions = []
            isLoading = true

            DispatchQueue.global(qos: .userInitiated).async {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }

                do {
                    let questions = try parseCSV(url: url)
                    DispatchQueue.main.async {
                        isLoading = false
                        if questions.isEmpty {
                            errorMessage = "Nie znaleziono pytań. Sprawdź format pliku."
                        } else {
                            parsedQuestions = questions
                            // Jeśli nazwa pusta, zaproponuj nazwę pliku
                            if name.trimmingCharacters(in: .whitespaces).isEmpty {
                                name = url.deletingPathExtension().lastPathComponent
                            }
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        isLoading = false
                        errorMessage = "Błąd odczytu: \(error.localizedDescription)"
                    }
                }
            }

        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Quiz View

struct QuizView: View {
    @StateObject var vm: QuizSessionViewModel

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    Text("\(vm.quizSet.questions.count) pytań w zestawie")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal)

                    if let q = vm.currentQuestion {
                        QuestionCard(question: q.question)
                        AnswersList(vm: vm)
                    } else {
                        QuizEmptyState()
                    }

                    HStack(spacing: 14) {
                        ActionButton(
                            title: "Losuj",
                            icon: "shuffle",
                            color: .accentColor
                        ) {
                            vm.drawQuestion()
                        }

                        ActionButton(
                            title: vm.showAnswer ? "Ukryj odpowiedź" : "Pokaż odpowiedź",
                            icon: vm.showAnswer ? "eye.slash" : "checkmark.seal",
                            color: vm.currentQuestion == nil ? .gray : (vm.showAnswer ? .orange : .green)
                        ) {
                            vm.toggleAnswer()
                        }
                        .disabled(vm.currentQuestion == nil)
                    }
                    .padding(.horizontal)
                    .padding(.top, 4)
                }
                .padding(.vertical)
            }
        }
        .navigationTitle(vm.quizSet.name)
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Question Card

struct QuestionCard: View {
    let question: String

    var body: some View {
        Text(question)
            .font(.title3.weight(.semibold))
            .multilineTextAlignment(.center)
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
            .padding(.horizontal)
    }
}

// MARK: - Answers List

struct AnswersList: View {
    @ObservedObject var vm: QuizSessionViewModel
    private let labels = ["A", "B", "C", "D"]

    var body: some View {
        // Filtrujemy "brak" przed przypisaniem liter, żeby litery były ciągłe (A, B, C)
        let visible = vm.shuffledAnswers.enumerated().filter { $0.element.text.lowercased() != "brak" }

        VStack(spacing: 10) {
            ForEach(Array(visible.enumerated()), id: \.offset) { labelIdx, pair in
                let (originalIdx, answer) = pair
                AnswerRow(
                    label: labels[labelIdx],
                    text: answer.text,
                    state: answerState(for: originalIdx)
                )
            }
        }
        .padding(.horizontal)
        .animation(.easeInOut(duration: 0.25), value: vm.showAnswer)
    }

    func answerState(for idx: Int) -> AnswerState {
        guard vm.showAnswer else { return .neutral }
        return vm.isCorrect(shuffledIndex: idx) ? .correct : .wrong
    }
}

enum AnswerState { case neutral, correct, wrong }

struct AnswerRow: View {
    let label: String
    let text: String
    let state: AnswerState

    var bg: Color {
        switch state {
        case .neutral: return Color(.secondarySystemGroupedBackground)
        case .correct: return Color.green.opacity(0.15)
        case .wrong:   return Color(.secondarySystemGroupedBackground)
        }
    }

    var borderColor: Color {
        state == .correct ? Color.green : Color.clear
    }

    var labelBg: Color {
        switch state {
        case .neutral: return Color.accentColor.opacity(0.12)
        case .correct: return Color.green
        case .wrong:   return Color.gray.opacity(0.15)
        }
    }

    var labelFg: Color {
        switch state {
        case .correct: return .white
        case .wrong:   return .secondary
        case .neutral: return .accentColor
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Text(label)
                .font(.headline)
                .foregroundStyle(labelFg)
                .frame(width: 34, height: 34)
                .background(labelBg)
                .clipShape(Circle())

            Text(text)
                .font(.body)
                .foregroundStyle(state == .wrong ? .secondary : .primary)
                .multilineTextAlignment(.leading)

            Spacer()

            if state == .correct {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: 1.5)
        )
    }
}

// MARK: - Quiz Empty State

struct QuizEmptyState: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "hand.tap")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Naciśnij 'Losuj', aby wyświetlić pierwsze pytanie")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
}

// MARK: - Action Button

struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(color)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}
