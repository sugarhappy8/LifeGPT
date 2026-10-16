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

                    guideSection("Choose a nation and an effective date", text: "Choose the nation and applicable region from the presets when starting a life, moving, or creating a business. A city or neighborhood can be described freely, but descriptive text does not change the saved jurisdiction. Your home, the company's location, and an employee's work location can differ.", example: "From 2004-11-13, the incorporated website business operates in Texas, United States. I still live in Texas. Keep its business account separate from my personal funds.", note: "Check the chosen preset before confirming. Tax profiles identify sourced rules and estimates for the story's date. Unsupported historical details and projections remain labeled estimates; moving does not rewrite earlier payments.")

                    guideSection("Distinguish revenue from profit", text: "Revenue is sales before payroll, operating expenses, and business taxes. Net profit is what remains after those costs. Include the currency, monthly amount, effective date, business, and receiving account. A recurring rate is not an immediate cash deposit.", example: "In Sandbox, my incorporated website now earns USD 50,000 gross revenue each month, before payroll, hosting, and taxes. Record this from the current game date in the website's business account. Replace its previous revenue rate; do not also add a net-profit income stream or a lump-sum deposit.", note: "Use this life's accounting currency. Existing net-income streams keep their original meaning until explicitly converted from a chosen date. Do not deduct the same business costs twice. In Simulation, describe your work and target, then record the outcome actually established.")

                    guideSection("Record employees and your salary", text: "Specify each employee's gross monthly pay and work jurisdiction. Employees with identical terms can share a staff-group record with a headcount and pay per person. Include start/end dates and identify the business that pays. Your own salary must be funded by the business account.", example: "Starting today, employ two developers in Texas at USD 4,000 gross per person per month, paid from the website business account. My gross owner salary is USD 1,500 per month from that account into my personal account. Apply the recorded employee deductions and employer charges. Do not invent other staff or wages.", note: "Gross salary and take-home pay differ when deductions apply. If business funds are insufficient, unpaid obligations remain visible; your personal savings are not silently used to cover them.")

                    guideSection("Record operating costs and changes", text: "Give each recurring cost a stable name, amount, paying business account, and effective date within the current turn. Say whether you are starting, replacing, or ending an existing agreement. A raise changes future pay; it does not rewrite settled months.", example: "From the current game date, change hosting to USD 800 per month and raise both developers to USD 4,500 gross each. Keep the existing payroll records and change their rates from today. Do not create duplicate employees.")

                    guideSection("Keep business and personal money separate", text: "Name the account whenever you earn, spend, or move money. Business profit belongs to the business account until you transfer some to yourself. Family support, access to a mansion, or company revenue does not automatically become personal spending money.", example: "Transfer USD 10,000 from my website's business account to my personal account as an owner's draw. Use existing business funds. This is a transfer, not new income.", note: "A transfer moves the same money between accounts. It must not also be recorded as a gift, wage, or extra profit, and it needs enough money in the source account.")

                    guideSection("Review a sale before handing over control", text: "Name the company, buyer, price, sale date, and destination for proceeds. A proposed sale appears for review and confirmation. Check which accounts and obligations transfer, the estimated tax, and any rights you keep. A completed full sale removes access to company funds; the company's cash is not also paid to you on top of the price.", example: "Prepare a sale of my entire website company to Northbridge for USD 2 million, effective on the current game date. Show the tax estimate and the company accounts and obligations that transfer. Put the sale proceeds into my personal account after I confirm the review.", note: "Closing an account also needs a destination for remaining cash and a resolution for linked obligations. Closed and transferred accounts keep their readable history.")

                    guideSection("Be explicit when time passes", text: "Give the exact amount of time and the focus of the skip. First confirm that the intended recurring income is recorded. Income and bills follow their recorded timing; describing a successful month does not itself create a payment. A new income stream does not imply back pay for earlier months.", example: "Skip exactly three months. I maintain the website at its recorded income rate and keep my current living arrangement. Apply the recurring income and expenses that fall due during this period. Keep business proceeds in the business account.")

                    guideSection("Check what was actually recorded", text: "Open Finances after a major change and after a time skip. Compare gross revenue, payroll, taxes, unpaid obligations, accessible balances, and the ledger with the story. Inspect business obligations separately from legacy income streams. For an exact account answer from your save, send ((accounts)); it does not call the narrator or advance time.", example: "((accounts))", note: "New business obligations accrue over the month and settle on the first of the next month, with partial months prorated. Legacy net-income streams retain their original month-boundary timing. A new rate does not deposit cash immediately when no time passes.")

                    guideSection("Correct the mismatch clearly", text: "Use the finance controls to inspect and change the recorded business, obligations, accounts, or legacy income. Specify the effective date and whether you are replacing an old record. Changes do not imply back pay or rewrite past ledger entries. You can also ask the narrator for the correction explicitly.", example: "My website's gross monthly revenue should be USD 50,000 from the current game date. My gross owner salary should be USD 1,500 funded by that business. Correct those records, end any duplicate net-income stream from the same date, and leave already-settled history unchanged.", note: "If a reply fails and Retry reply appears, Retry resubmits the same action, time skip, and reply length. It is for a failed turn, not an undo of a saved scene. To change the request, edit the action and send it again; editing or changing Story Settings clears the pending Retry.")

                    guideSection("Help the narrator find earlier context", text: "Name the person or business and roughly when an agreement happened. In Life & story settings, Look up earlier records can be Automatic, Always, or Off. A lookup requests relevant records from this life before the main reply. Current dates, finances, access rights, relationships, and commitments are always supplied.", example: "Remember the payroll agreement I made with Nora last May. Show how this month's expansion affects that agreement, using the recorded wages and dates.", note: "Lookup adds one model request when older records are available. It counts toward usage, including if the roleplay reply fails. Off uses local relevance matching. Prose drafting is separate, and a failed lookup falls back to local history without changing your life.")

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
