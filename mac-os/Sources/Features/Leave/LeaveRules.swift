import SwiftUI
import EffiLensKit

/// Leave rules shared with the web portal so both clients behave the same.
/// Ported from `frontend/src/lib/leave-utils.ts` (which mirrors the backend
/// PATCH / DELETE / approve rules in core-services `api/v1/leave.py`). The
/// server stays authoritative — these only decide which actions to offer.
enum LeaveRules {
    struct Actor {
        let id: UUID?
        let role: UserRole
    }

    private static func isAdmin(_ role: UserRole) -> Bool { role.atLeast(.admin) }

    /// System-created leave (hours-deficit / comp-off) can't be edited or cancelled (backend 409).
    static func isSystemLeave(_ a: LeaveApplication) -> Bool { a.sourceValue != .manual }

    static func canEdit(_ a: LeaveApplication, actor: Actor) -> Bool {
        guard !isSystemLeave(a), let status = a.statusValue else { return false }
        if isAdmin(actor.role) { return status != .rejected && status != .cancelled }
        if actor.role == .manager { return status.isPending }
        return a.userId == actor.id && status == .pendingManager
    }

    static func canCancel(_ a: LeaveApplication, actor: Actor) -> Bool {
        canEdit(a, actor: actor)   // identical rule set in the portal
    }

    enum ApproverLevel { case manager, admin }

    /// Which approve / reject endpoints this actor should call, if any.
    static func approverLevel(_ a: LeaveApplication, role: UserRole) -> ApproverLevel? {
        guard let status = a.statusValue else { return nil }
        if isAdmin(role) { return status.isPending ? .admin : nil }
        if role == .manager { return status == .pendingManager ? .manager : nil }
        return nil
    }

    /// "Full Day" / "Half Day" (portal `leaveTypeLabel`).
    static func dayTypeLabel(_ a: LeaveApplication) -> String {
        a.durationDays.doubleValue == 0.5 ? "Half Day" : "Full Day"
    }

    /// Backend unpaid-leave notice; reworded when someone else acted on the request.
    static func unpaidNotice(_ a: LeaveApplication, forApplicant: Bool) -> String? {
        guard let message = a.message, !message.isEmpty else { return nil }
        if forApplicant { return message }
        switch a.kind {
        case .unpaid: return "The employee has no paid leave available — this leave will be counted as unpaid."
        case .mixed: return "The employee's paid leave is not enough — part of this leave will be counted as unpaid."
        default: return message
        }
    }

    /// Portal Apply-form note on when paid / unpaid is decided.
    static func paymentDecisionNote(role: UserRole) -> String {
        isAdmin(role)
            ? "Paid or unpaid is decided now, when you submit, based on the balance and the monthly leave limit."
            : "Paid or unpaid is decided when an admin approves the request, based on your balance and the monthly leave limit."
    }
}

/// Portal `LeavePaymentLabel`: Paid / Unpaid / Paid + Unpaid / At approval,
/// with the day split for mixed requests.
struct LeavePaymentLabel: View {
    let application: LeaveApplication
    var showSplit = false

    private var color: Color {
        switch application.kind {
        case .paid: return Palette.success
        case .unpaid: return Palette.danger
        case .mixed: return Palette.warning
        case .pending, .none: return Palette.textTertiary
        case .holiday, .compensatory: return Palette.info
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(application.kind?.displayName ?? application.leaveType.capitalized)
                .font(Typo.bodyEmphasis).foregroundStyle(color)
            if showSplit, application.kind == .mixed {
                Text("\(Format.days(application.paidDays)) paid · \(Format.days(application.unpaidDays)) unpaid")
                    .font(Typo.small).foregroundStyle(Palette.textTertiary)
            }
        }
    }
}
