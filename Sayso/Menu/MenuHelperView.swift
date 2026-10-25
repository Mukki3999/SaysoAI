import PhotosUI
import SwiftUI

/// Photograph a menu, say what you want, get three picks. Everything runs on the iPhone.
struct MenuHelperView: View {
    @State private var model: MenuHelperViewModel
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var showCamera = false
    @FocusState private var typing: Bool
    @Environment(\.dismiss) private var dismiss

    private let seed: MenuSeed?

    init(modelAvailable: Bool, seed: MenuSeed? = nil) {
        _model = State(initialValue: MenuHelperViewModel(modelAvailable: modelAvailable))
        self.seed = seed
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        content
                    }
                    .padding(.horizontal, 20).padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
                if model.image != nil, model.modelAvailable, model.phase != .empty { inputBar }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.black)
        .presentationCornerRadius(36)
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            pickedPhoto = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { await model.load(data) }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { data in Task { await model.load(data) } }.ignoresSafeArea()
        }
        .task {
            if let seed, model.image == nil {
                await model.load(seed.data)
                if !seed.text.isEmpty { await model.submit(seed.text) }
            }
            #if DEBUG
            await DemoMenu.loadIfRequested(model)
            #endif
        }
    }

    // MARK: Pieces

    private var topBar: some View {
        HStack {
            Text("Menu").font(.system(size: 28, weight: .medium, design: .serif).italic()).foregroundStyle(.white)
            Spacer()
            if model.image != nil {
                photoButtons
            }
        }
        .padding(.horizontal, 20).padding(.top, 26).padding(.bottom, 12)
    }

    private var photoButtons: some View {
        HStack(spacing: 8) {
            if CameraPicker.isAvailable { roundButton("camera") { showCamera = true } }
            PhotosPicker(selection: $pickedPhoto, matching: .images) {
                Image(systemName: "photo").font(.system(size: 16, weight: .medium)).foregroundStyle(.white)
                    .frame(width: 40, height: 40).background(Color.white.opacity(0.12), in: Circle())
            }
            .accessibilityLabel("Choose a different photo")
        }
    }

    private func roundButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .medium)).foregroundStyle(.white)
                .frame(width: 40, height: 40).background(Color.white.opacity(0.12), in: Circle())
        }
        .accessibilityLabel("Take a photo")
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .empty:
            startCard
        case .reading(let message):
            if let image = model.image { MenuPhotoView(image: image, lines: model.lines, highlighted: []) }
            HStack(spacing: 10) { ProgressView().tint(.white); Text(message).foregroundStyle(.white.opacity(0.7)) }
                .padding(.top, 8)
        case .error(let message):
            startCard
            Text(message).font(.subheadline).foregroundStyle(.white.opacity(0.75))
        case .ready, .thinking:
            if let image = model.image {
                MenuPhotoView(image: image, lines: model.lines, highlighted: model.highlighted)
            }
            if model.modelAvailable { pickerSection } else { listSection }
        }
    }

    private var startCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "fork.knife").font(.system(size: 26, weight: .light)).foregroundStyle(.black)
            Text("Photograph a menu").font(.title2.weight(.semibold)).foregroundStyle(.black)
            Text(model.modelAvailable ? "Then say what you're in the mood for. Sayso picks three dishes from what's printed."
                                      : "Sayso reads it and lets you search and filter the dishes.")
                .font(.subheadline).foregroundStyle(.black.opacity(0.6))
            HStack(spacing: 10) {
                if CameraPicker.isAvailable { darkPill("Camera", symbol: "camera") { showCamera = true } }
                PhotosPicker(selection: $pickedPhoto, matching: .images) {
                    Label("Photos", systemImage: "photo").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 11).background(.black, in: Capsule())
                }
            }
            Text("The photo is read on your iPhone. It isn't saved or uploaded.").font(.caption).foregroundStyle(.black.opacity(0.45))
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(22)
        .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func darkPill(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                .padding(.horizontal, 18).padding(.vertical, 11).background(.black, in: Capsule())
        }
    }

    // MARK: With Apple Intelligence: picks

    private var pickerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            chips
            if model.prefs.isDefault && model.picks.isEmpty && model.phase != .thinking { suggestions }
            if model.phase == .thinking {
                HStack(spacing: 10) { ProgressView().tint(.white); Text("Picking…").foregroundStyle(.white.opacity(0.7)) }
            }
            ForEach(Array(model.picks.enumerated()), id: \.element.id) { i, pick in
                pickCard(pick, rank: i + 1).staggerIn(i)
            }
            if let outcome = model.outcome, model.picks.isEmpty, model.phase != .thinking, !model.prefs.isDefault {
                noMatchCard(outcome.hint ?? "Nothing matches that.")
            }
            if model.outcome?.budgetIgnored == true {
                Text("This menu shows no prices, so the budget wasn't applied.").font(.footnote).foregroundStyle(.white.opacity(0.55))
            }
            if let mic = model.micError { Text(mic).font(.footnote).foregroundStyle(.white.opacity(0.6)) }
        }
    }

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(model.prefs.chips) { chip in
                    Button { Task { await model.remove(chip) } } label: {
                        HStack(spacing: 6) {
                            Text(chip.label)
                            Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                        }
                        .font(.footnote.weight(.semibold)).foregroundStyle(.black)
                        .padding(.horizontal, 12).padding(.vertical, 8).background(.white, in: Capsule())
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var suggestions: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(["Something light", "Vegetarian", "Under $15", "Not too spicy", "What about dessert?"], id: \.self) { s in
                    Button { Task { await model.submit(s) } } label: {
                        Text(s).font(.footnote.weight(.medium)).foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 8).background(Color.white.opacity(0.14), in: Capsule())
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func pickCard(_ pick: MenuPick, rank: Int) -> some View {
        let selected = model.selectedID == pick.id
        return Button { model.select(pick.item) } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(rank)").font(.caption.weight(.bold)).foregroundStyle(.white)
                        .frame(width: 22, height: 22).background(.black, in: Circle())
                    Text(pick.item.name).font(.title3.weight(.semibold)).foregroundStyle(.black)
                    Spacer(minLength: 8)
                    if let p = pick.item.price {
                        Text("$\(MenuFilter.format(p))").font(.headline).foregroundStyle(.black)
                    }
                }
                Text(pick.reason).font(.subheadline).foregroundStyle(.black.opacity(0.75))
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle").font(.caption2)
                    Text(MenuHelperViewModel.disclaimer).font(.caption)
                }
                .foregroundStyle(.black.opacity(0.5))
                if selected {
                    Label("Shown on the photo", systemImage: "viewfinder").font(.caption.weight(.semibold)).foregroundStyle(.black.opacity(0.6))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(selected ? 1 : 0), lineWidth: 3).padding(-3))
        }
        .buttonStyle(CardPressStyle())
    }

    private func noMatchCard(_ hint: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No match").font(.headline).foregroundStyle(.black)
            Text(hint).font(.subheadline).foregroundStyle(.black.opacity(0.65))
            Text("Tap a chip above to loosen it, or ask for something else.").font(.footnote).foregroundStyle(.black.opacity(0.45))
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("What are you in the mood for?", text: $model.input, axis: .vertical)
                .focused($typing).lineLimit(1...3).submitLabel(.send)
                .onSubmit { Task { await model.submit() } }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            if model.input.trimmingCharacters(in: .whitespaces).isEmpty {
                Button { Task { await model.toggleMic() } } label: {
                    Image(systemName: model.isListening ? "waveform" : "mic.fill").font(.system(size: 18))
                        .foregroundStyle(.black).frame(width: 46, height: 46).background(.white, in: Circle())
                        .symbolEffect(.variableColor.iterative, isActive: model.isListening)
                }
                .accessibilityLabel(model.isListening ? "Stop listening" : "Say what you want")
            } else {
                Button { typing = false; Task { await model.submit() } } label: {
                    Image(systemName: "arrow.up").font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.black).frame(width: 46, height: 46).background(.white, in: Circle())
                }
                .accessibilityLabel("Send")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .overlay(alignment: .top) {
            if model.isListening {
                Text(model.speech.transcript.isEmpty ? "Listening…" : model.speech.transcript)
                    .font(.footnote).foregroundStyle(.white.opacity(0.7)).lineLimit(1).offset(y: -18)
            }
        }
    }

    // MARK: Without Apple Intelligence: searchable list

    private var listSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.5))
                TextField("Search dishes", text: $model.search).textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            filterRow(title: "Diet", options: [("Any", MenuPreferences.Diet.none), ("Vegetarian", .vegetarian), ("Vegan", .vegan), ("Pescatarian", .pescatarian)],
                      isOn: { model.prefs.diet == $0 }) { model.prefs.diet = $0; model.refreshList() }
            filterRow(title: "Price", options: [("Any", Double?.none), ("Under $10", 10), ("Under $15", 15), ("Under $20", 20), ("Under $30", 30)],
                      isOn: { model.prefs.maxPrice == $0 }) { model.prefs.maxPrice = $0; model.refreshList() }

            let shown = model.listItems
            Text("\(shown.count) \(shown.count == 1 ? "dish" : "dishes")").font(.caption.weight(.semibold)).tracking(0.8)
                .foregroundStyle(.white.opacity(0.45))
            if shown.isEmpty {
                noMatchCard(model.outcome?.hint ?? "No dishes match your search.")
            }
            ForEach(shown) { item in listRow(item) }
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle").font(.caption2)
                Text(MenuHelperViewModel.disclaimer).font(.caption)
            }
            .foregroundStyle(.white.opacity(0.5))
        }
    }

    private func filterRow<V>(title: String, options: [(String, V)], isOn: @escaping (V) -> Bool, set: @escaping (V) -> Void) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    let on = isOn(option.1)
                    Button { set(option.1) } label: {
                        Text(option.0).font(.footnote.weight(.semibold)).foregroundStyle(on ? .black : .white)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(on ? Color.white : Color.white.opacity(0.14), in: Capsule())
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityLabel(title)
    }

    private func listRow(_ item: MenuItem) -> some View {
        Button { model.select(item) } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.name).font(.headline).foregroundStyle(.black)
                    Spacer(minLength: 8)
                    if let p = item.price { Text("$\(MenuFilter.format(p))").font(.subheadline.weight(.semibold)).foregroundStyle(.black) }
                }
                if !item.description.isEmpty { Text(item.description).font(.subheadline).foregroundStyle(.black.opacity(0.6)) }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(model.selectedID == item.id ? 1 : 0), lineWidth: 3).padding(-3))
        }
        .buttonStyle(CardPressStyle())
    }
}
