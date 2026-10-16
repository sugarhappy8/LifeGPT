import SwiftUI

struct RoleplayGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("How to prompt for roleplay")
                    .font(.system(size: 28, design: .serif))
                    .accessibilityAddTraits(.isHeader)
                Text("Play the life you want, with a story and finances that agree.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    guideSection("Choose how this life plays", text: "In Story Settings, choose the play style for this life. Simulation resolves your attempts through the world's rules and uncertain outcomes. Sandbox accepts player-declared fictional outcomes and premises, while the engine still validates money and records. Difficulty controls uncertain challenges; it is separate from play style. The Swing Dial changes how strange the story can be.")

                    guideSection("Separate background from action", text: "Say what belongs to your approved background, what result you want, and what you do next. An approved starting background is already established. In Simulation, a desired new result is an attempt. In Sandbox, explicitly say when you are declaring a fictional outcome.", example: "My approved background is membership in a fictional royal family. My family covers my home and living costs; family wealth is separate from my personal cash. In this scene, I ask my cousin to introduce me to a business mentor.")

                    guideSection("Make recurring income specific", text: "Revenue is sales before business costs; net profit is what remains after those costs. Include the currency, amount, payment period, effective date, and receiving account. Say whether this replaces an existing income stream or adds a distinct source. A recurring rate is not an immediate lump-sum payment.", example: "In Sandbox, my website is now an established success. From the current in-game date, it earns USD 50,000 net profit per month after business expenses, paid into the website's business account. Record recurring income, replacing its previous rate. This is not a one-time USD 50,000 deposit.", note: "Use the life's accounting currency. If it is not USD, agree on an amount in that currency; do not assume automatic currency conversion. In Simulation, describe the work and target, then let the outcome determine the recorded rate.")

                    guideSection("Keep business and personal money separate", text: "Name the account whenever you earn, spend, or move money. Business profit belongs to the business account until you transfer some to yourself. Family support, access to a mansion, or company revenue does not automatically become personal spending money.", example: "Transfer USD 10,000 from my website's business account to my personal account as an owner's draw. Use existing business funds. This is a transfer, not new income.", note: "A transfer moves the same money between accounts. It must not also be recorded as a gift, wage, or extra profit, and it needs enough money in the source account.")

                    guideSection("Be explicit when time passes", text: "Give the exact amount of time and the focus of the skip. First confirm that the intended recurring income is recorded. Income and bills follow their recorded timing; describing a successful month does not itself create a payment. A new income stream does not imply back pay for earlier months.", example: "Skip exactly three months. I maintain the website at its recorded income rate and keep my current living arrangement. Apply the recurring income and expenses that fall due during this period. Keep business proceeds in the business account.")

                    guideSection("Check what was actually recorded", text: "Open Finances after a major change and after a time skip. Compare account balances, active income rates, and the recent ledger with the story. The header shows your recorded monthly income. For an exact answer from your save, send ((income)) or ((accounts)); these checks do not call the narrator or advance time.", example: "((income))", note: "Recurring payments arrive on the first of each calendar month crossed by a turn. A new rate does not deposit cash immediately when no time passes.")

                    guideSection("Correct the mismatch clearly", text: "Use Finances → Manage finances to start, change or end an income source directly, open accounts, or transfer existing cash. For a website, choose Business profit, enter the net monthly amount and receiving account, and apply it. These edits take effect on the current date without adding a story scene or back pay. You can also ask the narrator for the correction explicitly.", example: "The story said my website earns USD 50,000 net profit per month, but Finances still shows the old rate. Correct the recurring business income from the current in-game date. Do not add a duplicate lump sum or change my personal balance.", note: "If a reply fails and Retry reply appears, Retry resubmits the same action, time skip, and reply length. It is for a failed turn, not an undo of a saved scene. To change the request, edit the action and send it again; editing or changing Story Settings clears the pending Retry.")

                    guideSection("Tell the narrator what you enjoy", text: "Specify the pace, perspective, tone, and kind of scenes you want. Ask for ambitious successes, quiet everyday moments, detailed business decisions, or a family-focused story. Keep these storytelling preferences separate from financial instructions.", example: "Keep the story hopeful and ambitious, with short scenes and natural dialogue. Let me choose my character's words and decisions. When money changes, make the prose agree with the recorded accounts and explain any constraint plainly.")
                }
                .padding(.vertical, 8)
                .padding(.trailing, 10)
                .textSelection(.enabled)
            }

            HStack {
                Text("Select any example to copy and adapt it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(28)
        .frame(width: 680, height: 740)
    }

    private func guideSection(_ title: String, text: String, example: String? = nil, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text(text)
                .font(.callout)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            if let example {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Example prompt")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(example)
                        .font(.callout)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
            if let note {
                Text(note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
