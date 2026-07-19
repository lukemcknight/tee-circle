import Messages
import SwiftUI
import TeeCircleDomain
import UIKit

@MainActor
final class MessagesViewController: MSMessagesAppViewController {
    private let model = MessagesViewModel()
    private var hostController: UIHostingController<MessagesRootView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        installSwiftUIHost()
        updatePresentationMode(presentationStyle)
    }

    override func willBecomeActive(with conversation: MSConversation) {
        super.willBecomeActive(with: conversation)
        updatePresentationMode(presentationStyle)
        model.activate(selectedMessageURL: conversation.selectedMessage?.url)
    }

    override func didSelect(_ message: MSMessage, conversation: MSConversation) {
        super.didSelect(message, conversation: conversation)
        model.activate(selectedMessageURL: message.url)
    }

    override func willTransition(to presentationStyle: MSMessagesAppPresentationStyle) {
        super.willTransition(to: presentationStyle)
        updatePresentationMode(presentationStyle)
    }

    override func didTransition(to presentationStyle: MSMessagesAppPresentationStyle) {
        super.didTransition(to: presentationStyle)
        updatePresentationMode(presentationStyle)
    }

    private func installSwiftUIHost() {
        let actions = MessagesHostActions(
            requestExpanded: { [weak self] in
                self?.requestPresentationStyle(.expanded)
            },
            postSnapshot: { [weak self] trip, final in
                self?.stageMessage(for: trip, final: final)
            },
            reconnect: { [weak self] url in
                guard let url else { return }
                self?.extensionContext?.open(url, completionHandler: nil)
            }
        )
        let root = MessagesRootView(model: model, actions: actions)
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear

        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
        hostController = host
    }

    private func updatePresentationMode(_ style: MSMessagesAppPresentationStyle) {
        switch style {
        case .compact:
            model.presentationMode = .compact
        case .expanded:
            model.presentationMode = .expanded
        case .transcript:
            model.presentationMode = .transcript
        @unknown default:
            model.presentationMode = .compact
        }
    }

    private func stageMessage(for trip: CachedMessagesTripV1, final: Bool) {
        guard let conversation = activeConversation,
              let canonicalURL = MessagesConfiguration.current.inviteURL(token: trip.inviteToken)
        else {
            model.didFailToQueueMessage()
            return
        }

        let template = makeTemplate(for: trip, final: final)
        let layout = MSMessageLiveLayout(alternateLayout: template)
        let session = reusableSession(in: conversation, canonicalURL: canonicalURL)
        let message = MSMessage(session: session)
        message.layout = layout
        message.url = canonicalURL
        message.shouldExpire = false

        let leader = trip.snapshot.primaryBoard?.standings.first
        let through = trip.snapshot.currentRound?.throughHole ?? 0
        let invite = isInvite(trip, final: final)
        if invite {
            message.summaryText = "You’re invited to a TeeCircle round at \(trip.trip.name)"
            message.accessibilityLabel = "Invitation to \(trip.trip.name). Open the link to see the tee time and join the round."
        } else if final {
            message.summaryText = "Final TeeCircle result for \(trip.trip.name)"
            message.accessibilityLabel = finalAccessibilityLabel(trip: trip, leader: leader)
        } else {
            message.summaryText = "TeeCircle standings captured through \(through)"
            message.accessibilityLabel = standingsAccessibilityLabel(trip: trip, leader: leader)
        }

        conversation.insert(message) { [weak self] error in
            Task { @MainActor in
                if error == nil {
                    self?.model.didQueueMessage(final: final, lifecycle: trip.trip.lifecycle)
                } else {
                    self?.model.didFailToQueueMessage()
                }
            }
        }
    }

    private func reusableSession(in conversation: MSConversation, canonicalURL: URL) -> MSSession {
        guard let selected = conversation.selectedMessage,
              selected.url == canonicalURL,
              let session = selected.session
        else { return MSSession() }
        return session
    }

    private func makeTemplate(for trip: CachedMessagesTripV1, final: Bool) -> MSMessageTemplateLayout {
        let template = MSMessageTemplateLayout()
        let leader = trip.snapshot.primaryBoard?.standings.first
        let through = trip.snapshot.currentRound?.throughHole ?? 0
        let invite = isInvite(trip, final: final)
        template.caption = trip.trip.name
        template.subcaption = invite
            ? "Open to see the tee time and claim a spot"
            : (final
                ? "Final result · revision \(trip.snapshot.revision)"
                : "Captured through \(through) · revision \(trip.snapshot.revision)")
        template.trailingCaption = invite ? "ROUND" : trip.snapshot.primaryFormat.rawValue.capitalized
        template.trailingSubcaption = invite ? "INVITE" : trip.trip.scoringMode.rawValue.capitalized
        template.imageTitle = invite ? "ROUND INVITE" : (final ? "FINAL RESULTS" : "STANDINGS SNAPSHOT")
        template.imageSubtitle = invite ? "Tap to join on TeeCircle" : "Open the link for the current board"
        template.image = renderCardImage(trip: trip, leader: leader, final: final)
        return template
    }

    private func renderCardImage(
        trip: CachedMessagesTripV1,
        leader: LeaderboardStandingV1?,
        final: Bool
    ) -> UIImage {
        let size = CGSize(width: 720, height: 430)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let invite = isInvite(trip, final: final)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let bounds = CGRect(origin: .zero, size: size)
            UIColor(red: 0.018, green: 0.095, blue: 0.07, alpha: 1).setFill()
            context.fill(bounds)

            let lime = UIColor(red: 25 / 255, green: 235 / 255, blue: 102 / 255, alpha: 1)
            draw(
                invite ? "TEE CIRCLE  ·  ROUND INVITE" : (final ? "TEE CIRCLE  ·  FINAL" : "TEE CIRCLE  ·  SENT SNAPSHOT"),
                in: CGRect(x: 42, y: 38, width: 636, height: 34),
                font: .systemFont(ofSize: 22, weight: .black),
                color: lime,
                tracking: 2.2
            )
            draw(
                trip.trip.name,
                in: CGRect(x: 42, y: 92, width: 636, height: 92),
                font: .systemFont(ofSize: 44, weight: .heavy),
                color: .white
            )

            if invite {
                draw(
                    "You’re invited.",
                    in: CGRect(x: 42, y: 218, width: 636, height: 72),
                    font: .systemFont(ofSize: 48, weight: .heavy),
                    color: .white
                )
            } else if let leader {
                draw(
                    leader.displayName,
                    in: CGRect(x: 42, y: 220, width: 440, height: 72),
                    font: .systemFont(ofSize: 50, weight: .heavy),
                    color: .white
                )
                draw(
                    "\(leader.value)",
                    in: CGRect(x: 500, y: 205, width: 178, height: 90),
                    font: .monospacedDigitSystemFont(ofSize: 70, weight: .black),
                    color: lime,
                    alignment: .right
                )
            } else {
                draw(
                    "Standings ready",
                    in: CGRect(x: 42, y: 220, width: 636, height: 72),
                    font: .systemFont(ofSize: 46, weight: .heavy),
                    color: .white
                )
            }

            let through = trip.snapshot.currentRound?.throughHole ?? 0
            let footer = invite
                ? "TAP TO JOIN  ·  PRIVATE LINK"
                : (final
                    ? "FINAL  ·  REVISION \(trip.snapshot.revision)"
                    : "THROUGH \(through)  ·  REVISION \(trip.snapshot.revision)")
            draw(
                footer,
                in: CGRect(x: 42, y: 345, width: 636, height: 36),
                font: .monospacedSystemFont(ofSize: 22, weight: .bold),
                color: UIColor.white.withAlphaComponent(0.7),
                tracking: 1
            )
        }
    }

    private func draw(
        _ text: String,
        in rect: CGRect,
        font: UIFont,
        color: UIColor,
        tracking: CGFloat = 0,
        alignment: NSTextAlignment = .left
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: [
                .font: font,
                .foregroundColor: color,
                .kern: tracking,
                .paragraphStyle: paragraph,
            ],
            context: nil
        )
    }

    private func standingsAccessibilityLabel(
        trip: CachedMessagesTripV1,
        leader: LeaderboardStandingV1?
    ) -> String {
        let through = trip.snapshot.currentRound?.throughHole ?? 0
        if let leader {
            if leader.tied {
                return "TeeCircle standings for \(trip.trip.name), captured through hole \(through). \(leader.displayName) is tied for first with \(leader.value). Open the link for current scores."
            }
            return "TeeCircle standings for \(trip.trip.name), captured through hole \(through). \(leader.displayName) is first with \(leader.value). Open the link for current scores."
        }
        return "TeeCircle standings for \(trip.trip.name), captured through hole \(through). Open the link for current scores."
    }

    private func finalAccessibilityLabel(
        trip: CachedMessagesTripV1,
        leader: LeaderboardStandingV1?
    ) -> String {
        if let leader {
            if leader.tied {
                return "Final TeeCircle result for \(trip.trip.name). \(leader.displayName) finished tied for first with \(leader.value)."
            }
            return "Final TeeCircle result for \(trip.trip.name). \(leader.displayName) finished first with \(leader.value)."
        }
        return "Final TeeCircle result for \(trip.trip.name)."
    }

    private func isInvite(_ trip: CachedMessagesTripV1, final: Bool) -> Bool {
        !final && [.draft, .ready].contains(trip.trip.lifecycle)
    }
}
