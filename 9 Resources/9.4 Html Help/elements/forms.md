# Forms

HTML forms collect user input and submit it to a server or process it client-side.

---

## Core Elements

| Element | Purpose |
|---------|---------|
| `<form>` | Form container — defines action, method, and submission behaviour |
| `<input>` | Single-line input — text, email, password, number, checkbox, radio, file, date, and more |
| `<textarea>` | Multi-line text input |
| `<select>` | Dropdown list with `<option>` children |
| `<button>` | Clickable button — can be `type="submit"`, `"reset"`, or `"button"` |
| `<label>` | Text label linked to an input via `for` attribute (matches input `id`) |

## Input Types

- **`text`**: Default single-line text.
- **`email`**: Validates email format on submission.
- **`password`**: Masks input characters.
- **`number`**: Numeric input with increment/decrement arrows.
- **`checkbox`**: Binary on/off toggle.
- **`radio`**: Single selection from a group (same `name` attribute).
- **`date`**, **`time`**, **`color`**: Browser-native pickers.
- **`file`**: File upload selector.

## Form Attributes

- **`action`**: URL where form data is sent.
- **`method`**: `GET` (data in URL) or `POST` (data in request body).
- **`enctype`**: Use `multipart/form-data` for file uploads.
- **`novalidate`**: Disables browser validation.

## Accessibility

- Every input should have an associated `<label>`.
- Use `<fieldset>` and `<legend>` to group related inputs.
- Add `required` attribute for mandatory fields, `aria-describedby` for help text.
