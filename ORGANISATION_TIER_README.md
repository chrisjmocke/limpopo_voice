# LET'S TALK Organisation Tier (Pool and Invite)

This document describes the Organisation tier implementation for shared credits...

## 1. Firestore Data Structure

### organizations/{organizationId}
- name: string
- ownerUid: string
- inviteCode: string (example: LT-ORG-1234)
- sharedCredits: number
- tierType: string (organization)
- createdAt: timestamp
- updatedAt: timestamp

### users/{userId}
- organizationId: string (optional)
- organizationRole: string (owner or member)
- organizationInviteCode: string (optional)
- organizationName: string (optional)
- updatedAt: timestamp

## 2. App Flow

### Buy Organisation Tier
1. User opens Credits popup and selects Organisation tier.
2. User picks payment gateway.
3. On payment success:
   - If user has no organization, app creates one.
   - If user already has one, app tops up sharedCredits.
   - User is stored as organization owner.
   - Invite code is shown and can be copied.

### Join Organisation by Invite Code
1. User opens User menu and taps Join Organisation.
2. User enters invite code.
3. App finds matching organization by inviteCode.
4. App links users/{userId} to organizationId with role member.

### Owner Management (Rename and Regenerate)
1. Owner opens User menu and taps Manage Organisation.
2. Owner can rename the organization.
3. Owner can regenerate a new invite code.
4. Updates are written to both organizations/{organizationId} and users/{userId}.

### Spend Credits During Translation
1. App checks if user belongs to an organization.
2. If yes, app debits 1 credit from organization shared pool in a transaction.
3. If not, app uses personal credit balance.

### Activity Logs
Organization activity is recorded in:
- organizations/{organizationId}/activity/{eventId}

Logged actions include:
- pool_created
- pool_topped_up
- credit_spent
- settings_updated

In-app access:
- User menu -> Organisation Activity (visible when linked to an organization)
- Displays latest events with timestamp, credit delta, pool balance, role, and tier

## 3. Rules Model

See firestore.rules for enforced permissions:
- User can read/write own user doc.
- Any signed-in user can read organizations.
- Owner can create/update/delete own organization.
- Members can only update organization when sharedCredits decreases by exactly 1 and protected fields stay unchanged.

## 4. Important Note

Firebase Auth anonymous sign-in is now used to establish request.auth.uid.
User profile docs are keyed by auth UID in users/{uid}, while installId is stored as metadata.

## 5. Paystack Sandbox Testing

If PAYSTACK_TEST_ACCESS_CODE is not set, the app can still run test purchases in sandbox simulation mode.

- Default behavior: enabled in debug builds.
- Optional env override: set PAYSTACK_SANDBOX_BYPASS=true in .env to force-enable simulation.
- Simulation writes payment events with status:
   - completed_sandbox_paystack_simulated
