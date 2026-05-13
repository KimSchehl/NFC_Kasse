# UC03 — User Management & Permission Assignment

**Actor:** Event manager or admin  
**Precondition:** Has `users.create` and `users.manage_permissions`

---

## Create a New Staff Member

```
1. Settings screen → User management
2. "New user" → enter username + password
   → POST /api/users/
3. Optional: apply role template
   → POST /api/users/{id}/apply-template/{template_id}
   → Template sets predefined permissions (e.g. "Standverkäufer")
4. Assign category access:
   → Checkbox list of all categories for this event
   → PUT /api/users/{id}/categories with [category_ids]
```

---

## Permission Tree UI (`widgets/permission_tree.dart`)

```
Sales
  ☑ Booking
    ☑ Create booking
    ☑ Cancel (5 minutes)
    ☐ Cancel (unlimited)
  ☑ Balance
    ☑ View balance
    ☐ Top-up balance
    ☐ Payout
Categories
  ☑ View categories
    ├─ ☑ Bar
    ├─ ☐ Essen
    └─ ☐ Bonkasse
...
```

→ Each leaf checkbox = one `user_permission` row  
→ Category checkboxes = `user_category_access` rows

---

## Role Templates

| Template (German content) | Included Permissions |
|---|---|
| Standverkäufer | sales.booking.create, cancel_5min, balance.view, products.view, categories.view, settings.local |
| Veranstaltungs-Verantwortlicher | All of the above + topup, payout, products.edit/price/deactivate/activate, categories.create/edit, all statistics, users.view, settings.event |

Templates speed up onboarding — individual adjustments are possible afterwards.
