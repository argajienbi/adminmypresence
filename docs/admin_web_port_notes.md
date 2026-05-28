# admin_web Port Notes

Source repo: `argajienbi/admin_web`

Source commit inspected: `210a994 Add project blueprint handoff notes`

Port focus in this Flutter project:

- RTDB path helpers now mirror `src/services/paths.ts`.
- Firestore path helpers now mirror `src/services/firestorePaths.ts`.
- QR approval resolves schedule data and writes approved attendance records to `/attendance/{company_id}/{uid}/{date}/{action_type}`.
- Leave and QR approval write audit logs and user notifications.
- Notifications use the Firestore feature layer:
  - `companies/{companyId}/users/{uid}/notification_inbox`
  - `companies/{companyId}/notification_queue`
  - `companies/{companyId}/notification_logs`
  - `companies/{companyId}/notification_settings/main`
- Announcements use `companies/{companyId}/announcements` with RTDB fallback reads for legacy data.

The source React app still has richer desktop UI controls than this Flutter port. This port prioritizes data compatibility and admin workflows on mobile.
