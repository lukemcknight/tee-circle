import SwiftUI
import TeeCircleDomain
import TeeCircleAPI

/// The original TeeCircle promise, rebuilt on the native trip model. A simple
/// round is stored as a one-round trip so invites, scoring, and Messages all use
/// the same secure backend without exposing planner complexity to the player.
struct CreateRoundView: View {
    @EnvironmentObject private var store: TeeCircleStore
    @FocusState private var courseIsFocused: Bool

    @State private var courseName = ""
    @State private var selectedCourseCardID: String?
    @State private var teeTime = Self.defaultTeeTime
    @State private var holeCount = 18
    @State private var walkRide = "ride"
    @State private var guestNames = [""]
    @State private var isCreating = false
    @StateObject private var courseSearch = CourseSearchController(
        apiKey: AppConfiguration.load().googlePlacesAPIKey
    )
    @State private var suppressCourseSearch = false

    var body: some View {
        ZStack {
            BroadcastBackground()

            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        pageLead
                        courseSection
                        scheduleSection
                        roundTicket
                        groupSection
                        messagesNote
                    }
                    .frame(width: max(geometry.size.width - 36, 0), alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 118)
                }
                .scrollDismissesKeyboard(.interactively)
                .accessibilityIdentifier("round.formScroll")
            }
        }
        .navigationTitle("New round")
        .navigationBarTitleDisplayMode(.inline)
        // This screen pins its own action bar, and two stacked bottom chromes
        // both crowd the form and give a half-finished round an easy exit.
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom) { actionBar }
        .onChange(of: holeCount) { newValue in
            guard let selectedCourseCardID,
                  store.courseCards.first(where: { $0.id == selectedCourseCardID })?.holes.count != newValue
            else { return }
            self.selectedCourseCardID = nil
        }
        .onChange(of: courseName) { newValue in
            if suppressCourseSearch {
                suppressCourseSearch = false
                return
            }
            guard courseIsFocused else { return }
            courseSearch.update(query: newValue)
        }
        .onChange(of: courseIsFocused) { focused in
            if !focused { courseSearch.dismiss() }
        }
    }

    private var pageLead: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("MAKE THE TEE TIME")
                .font(.caption.weight(.black))
                .tracking(1.7)
                .foregroundStyle(TeeCircleBrand.signal)

            Text("One round.\nYour people.")
                .font(.system(size: 38, weight: .black, design: .rounded))
                .tracking(-1.4)
                .lineSpacing(-3)

            Text("Set the essentials now. TeeCircle makes the invite link and keeps the yeses and nos in one place.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var roundTicket: some View {
        HStack(spacing: 16) {
            VStack(spacing: 2) {
                Text(teeTime.formatted(.dateTime.month(.abbreviated)).uppercased())
                    .font(.caption2.weight(.black))
                    .tracking(1)
                    .foregroundStyle(TeeCircleBrand.signal)
                Text(teeTime.formatted(.dateTime.day()))
                    .font(.system(size: 30, weight: .black, design: .rounded))
            }
            .frame(width: 60, height: 68)
            .background(TeeCircleBrand.signal.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(TeeCircleBrand.signal.opacity(0.2))
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(courseName.nonEmpty ?? "Course to be decided")
                    .font(.headline.weight(.bold))
                    .lineLimit(1)
                Text("\(teeTime.formatted(date: .omitted, time: .shortened))  ·  \(holeCount) holes  ·  \(walkRide == "walk" ? "Walking" : "Riding")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Image(systemName: "flag.fill")
                .font(.title3.weight(.black))
                .foregroundStyle(TeeCircleBrand.signal)
                .accessibilityHidden(true)
        }
        .padding(17)
        .teeCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(roundSummary)
    }

    private var courseSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(number: "01", title: "Where are you playing?")

            HStack(spacing: 11) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(TeeCircleBrand.signal)
                    .accessibilityHidden(true)

                TextField(
                    "Course name",
                    text: $courseName,
                    prompt: Text("Bethpage Black").foregroundColor(.secondary)
                )
                .font(.headline)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .focused($courseIsFocused)
                .onSubmit { courseIsFocused = false }
                .accessibilityIdentifier("round.course")

                if !courseName.isEmpty {
                    Button {
                        courseName = ""
                        selectedCourseCardID = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear course")
                }
            }
            .padding(.horizontal, 15)
            .frame(minHeight: 54)
            .background(TeeCircleBrand.raisedCard, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(courseIsFocused ? TeeCircleBrand.signal.opacity(0.7) : TeeCircleBrand.hairline)
            }

            if courseSearch.isEnabled {
                CourseSearchSuggestionList(controller: courseSearch) { prediction in
                    Task {
                        suppressCourseSearch = true
                        courseName = await courseSearch.select(prediction)
                        selectedCourseCardID = nil
                        courseIsFocused = false
                    }
                }
            }

            if !store.courseCards.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    Text("SAVED CARDS")
                        .font(.caption2.weight(.black))
                        .tracking(1.2)
                        .foregroundStyle(TeeCircleBrand.moss)

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 138), spacing: 9)],
                        alignment: .leading,
                        spacing: 9
                    ) {
                        ForEach(store.courseCards) { card in
                            Button {
                                selectedCourseCardID = card.id
                                courseName = card.name
                                holeCount = card.holes.count <= 9 ? 9 : 18
                            } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: selectedCourseCardID == card.id ? "checkmark.circle.fill" : "flag.circle")
                                    Text(card.teeName.map { "\(card.name) · \($0)" } ?? card.name)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .font(.caption.weight(.bold))
                                .foregroundStyle(selectedCourseCardID == card.id ? TeeCircleBrand.forest : TeeCircleBrand.ink)
                                .padding(.horizontal, 12)
                                .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                                .background(
                                    selectedCourseCardID == card.id ? TeeCircleBrand.signal : TeeCircleBrand.raisedCard,
                                    in: Capsule()
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(18)
        .teeCard()
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 17) {
            sectionHeader(number: "02", title: "When and how?")

            HStack(spacing: 12) {
                compactDateField(title: "DATE", icon: "calendar") {
                    DatePicker(
                        "Date",
                        selection: $teeTime,
                        in: Date.now...,
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .accessibilityIdentifier("round.date")
                }

                compactDateField(title: "TEE TIME", icon: "clock") {
                    DatePicker("Tee time", selection: $teeTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .accessibilityIdentifier("round.time")
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                Text("LENGTH")
                    .font(.caption2.weight(.black))
                    .tracking(1.2)
                    .foregroundStyle(TeeCircleBrand.moss)

                HStack(spacing: 8) {
                    choiceButton(title: "18 holes", icon: "18.circle.fill", selected: holeCount == 18) {
                        holeCount = 18
                    }
                    .accessibilityIdentifier("round.length.18")

                    choiceButton(title: "9 holes", icon: "9.circle.fill", selected: holeCount == 9) {
                        holeCount = 9
                    }
                    .accessibilityIdentifier("round.length.9")
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                Text("GETTING AROUND")
                    .font(.caption2.weight(.black))
                    .tracking(1.2)
                    .foregroundStyle(TeeCircleBrand.moss)

                HStack(spacing: 8) {
                    choiceButton(title: "Riding", icon: "car.fill", selected: walkRide == "ride") {
                        walkRide = "ride"
                    }
                    .accessibilityIdentifier("round.transport.ride")

                    choiceButton(title: "Walking", icon: "figure.walk", selected: walkRide == "walk") {
                        walkRide = "walk"
                    }
                    .accessibilityIdentifier("round.transport.walk")
                }
            }
        }
        .padding(18)
        .teeCard()
    }

    private var groupSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            sectionHeader(number: "03", title: "Who is in the group?")

            Text("Names are optional. Add them now or send the link and let friends claim their spot.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            playerRow(name: .constant(store.currentDisplayName), index: 0, locked: true)

            ForEach(guestNames.indices, id: \.self) { index in
                playerRow(name: $guestNames[index], index: index + 1, locked: false)
            }

            Button {
                guestNames.append("")
            } label: {
                Label("Add another name", systemImage: "person.badge.plus")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(TeeCircleBrand.signal)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("round.addGuest")
        }
        .padding(18)
        .teeCard()
    }

    private var messagesNote: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: "message.fill")
                .font(.headline)
                .foregroundStyle(TeeCircleBrand.signal)
                .frame(width: 38, height: 38)
                .background(TeeCircleBrand.signal.opacity(0.1), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("Built for the group chat")
                    .font(.subheadline.weight(.bold))
                Text("Your round gets a private invite link you can send in Messages as soon as it is created.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 4)
    }

    private var actionBar: some View {
        VStack(spacing: 7) {
            Button(action: createRound) {
                HStack(spacing: 10) {
                    if isCreating {
                        ProgressView().tint(TeeCircleBrand.forest)
                    }
                    Text(isCreating ? "Making the round…" : "Create round")
                    if !isCreating { Image(systemName: "arrow.up.right") }
                }
                .font(.headline.weight(.black))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .foregroundStyle(TeeCircleBrand.forest)
                .background(TeeCircleBrand.signal, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                .shadow(color: TeeCircleBrand.signal.opacity(canCreate ? 0.22 : 0), radius: 16, y: 8)
            }
            .buttonStyle(.plain)
            .disabled(!canCreate || isCreating)
            .opacity(canCreate ? 1 : 0.42)
            .accessibilityIdentifier("round.submit")

            Text("Invite friends from the next screen")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 9)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Rectangle().fill(TeeCircleBrand.hairline).frame(height: 1) }
    }

    private func sectionHeader(number: String, title: String) -> some View {
        HStack(spacing: 10) {
            Text(number)
                .font(.caption.monospaced().weight(.black))
                .foregroundStyle(TeeCircleBrand.signal)
            Text(title)
                .font(.title3.weight(.black))
        }
    }

    private func compactDateField<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption2.weight(.black))
                .tracking(0.9)
                .foregroundStyle(TeeCircleBrand.moss)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TeeCircleBrand.raisedCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func choiceButton(
        title: String,
        icon: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title)
                    .font(.subheadline.weight(.bold))
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark").font(.caption.weight(.black)) }
            }
            .foregroundStyle(selected ? TeeCircleBrand.forest : TeeCircleBrand.ink)
            .padding(.horizontal, 13)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(selected ? TeeCircleBrand.signal : TeeCircleBrand.raisedCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                if !selected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(TeeCircleBrand.hairline)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func playerRow(name: Binding<String>, index: Int, locked: Bool) -> some View {
        HStack(spacing: 12) {
            Text(index == 0 ? store.currentDisplayName.prefix(1).uppercased() : "\(index + 1)")
                .font(.subheadline.monospaced().weight(.black))
                .foregroundStyle(index == 0 ? TeeCircleBrand.forest : TeeCircleBrand.moss)
                .frame(width: 36, height: 36)
                .background(index == 0 ? TeeCircleBrand.signal : TeeCircleBrand.raisedCard, in: Circle())

            if locked {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.currentDisplayName).font(.subheadline.weight(.bold))
                    Text("HOST").font(.caption2.weight(.black)).tracking(1).foregroundStyle(TeeCircleBrand.moss)
                }
            } else {
                TextField("Friend’s name (optional)", text: name)
                    .font(.subheadline.weight(.semibold))
                    .textInputAutocapitalization(.words)
                    .accessibilityIdentifier("round.guest.\(index)")
            }

            Spacer()

            if !locked, !name.wrappedValue.isEmpty {
                Button { name.wrappedValue = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear friend name")
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 54)
        .background(TeeCircleBrand.raisedCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var canCreate: Bool {
        courseName.nonEmpty != nil
    }

    private var roundSummary: String {
        "Round at \(courseName.nonEmpty ?? "course to be decided"), \(teeTime.formatted(date: .abbreviated, time: .shortened)), \(holeCount) holes, \(walkRide == "walk" ? "walking" : "riding")"
    }

    private func createRound() {
        guard canCreate, !isCreating else { return }
        courseIsFocused = false
        isCreating = true

        let normalizedCourse = courseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedCard = selectedCourseCardID.flatMap { id in
            store.courseCards.first(where: { $0.id == id && $0.holes.count == holeCount })
        }
        let holes = selectedCard?.holes.map {
            RoundHole(number: $0.number, par: $0.par, strokeIndex: $0.strokeIndex)
        } ?? Array(CreateTripDraft.standardHoles.prefix(holeCount))

        let draft = CreateTripDraft.singleRound(
            courseName: normalizedCourse,
            teeTime: teeTime,
            holeCount: holeCount,
            walkRide: walkRide,
            playerNames: [store.currentDisplayName] + guestNames.compactMap(\.nonEmpty),
            holes: holes
        )

        Task {
            if let id = await store.submitTrip(from: draft) {
                if !store.path.isEmpty { store.path.removeLast() }
                store.path.append(.trip(id))
            }
            isCreating = false
        }
    }

    private static var defaultTeeTime: Date {
        let calendar = Calendar.current
        let start = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: .now) ?? .now
        if start > .now { return start }
        return calendar.date(byAdding: .day, value: 1, to: start) ?? start
    }
}

private extension String {
    var nonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
