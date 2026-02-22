# Multi-Agent Organization Architecture (B2B SaaS Shift)
**Goal:** Transition PennyWise from single-user to an Organization-First model. Every signed-up user is an orgAdmin, who can invite agents via an Invite Code. Agents inherit the Org's business details, logo, address, and theme.

## Step 1: Data Modeling & Schema (`lib/models.dart`)
1. Create `UserRole` enum (`admin`, `agent`).
2. Add `orgId` (String?) and `role` (UserRole) to `BusinessProfile`.
3. Create new `Organization` class:
   - `id` (orgId)
   - `inviteCode` (6-char alphanumeric string)
   - `businessName`, `businessAddress`, `displayPhoneNumber`
   - `logoUrl`, `bankName`, `accountNumber`, `accountName`
   - `themeIndex`
4. Update `OnboardingStatus` enum with:
   - `awaiting_setup_choice` (1 for Create, 2 for Join)
   - `awaiting_invite_code`
5. Run `flutter pub run build_runner build --delete-conflicting-outputs` to update `models.g.dart`.

## Step 2: Database Layer (`lib/firestore_service.dart`)
1. Add function `createOrganization(String ownerPhone, String businessName)` which generates a unique 6-character code and returns the `orgId`.
2. Add function `getOrganization(String orgId)` to retrieve the org data.
3. Add function `findOrganizationByInviteCode(String code)` to link agents.
4. Refactor existing `updateProfileData` and `saveLogoUrl` so they update the `organizations/{orgId}` document instead of the user document (for admins).
5. **Legacy Migration Method:** If a user messages the bot and lacks an `orgId`, automatically migrate their legacy profile data into a new Organization document.

## Step 3: Core Logic & Routing (`routes/webhook.dart`)
1. **Entry Point Change:** When a new user messages, ask: "Create New Business or Join Team?".
2. **Setup Flow Split:**
   - Create: Proceed to `awaiting_address` and generate Org doc in the background.
   - Join: Move to `awaiting_invite_code` state -> validate -> link to Org -> `active`.
3. **Role-Based Menus (`_handleGlobalCommands`):**
   - Admin sees full menu + "5️⃣ Invite Team Member" (Displays the invite code).
   - Agent sees limited menu (Create Receipt, View Stats).
4. **Agent Action restrictions:** Prevent agents from triggering `UserAction.editProfileMenu`, `editLogo`, etc.
5. **PDF Generation Preparation:** In `_processReceiptResult` / `_handleThemeSelection`, fetch the `Organization` using `profile.orgId` and pass it to the PDF function.

## Step 4: PDF Generation (`lib/pdf_service.dart`)
1. Modify `generateReceipt` to accept an `Organization` object instead of (or alongside) `BusinessProfile`.
2. Ensure logo, business name, address, phone, theme, and bank details are all read straight from the `Organization` object, guaranteeing a uniform look for both admins and agents.

## Step 5: Supervision & Analytics (Gemini Prompting)
1. Add an intent specifically for "Team Stats" or "My Stats".
2. If admin: "Fetch all receipts for this orgId today" -> summarize.
3. If agent: "Fetch all receipts for this userId today" -> summarize.

---

### Progress Tracking
- [ ] Step 1: Data Modeling
- [ ] Step 2: Database Layer
- [ ] Step 3: Logic & Routing
- [ ] Step 4: PDF Update
- [ ] Step 5: Analytics
