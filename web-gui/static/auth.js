document.addEventListener('DOMContentLoaded', () => {
    const signupForm = document.getElementById('signup-form');
    const loginForm = document.getElementById('login-form');
    const messageArea = document.getElementById('message-area');

    // --- Helper to display success/error messages ---
    const displayMessage = (message, type) => {
        messageArea.textContent = message;
        messageArea.className = type; // 'success' or 'error'
    };

    // --- Sign Up Form Handler ---
    signupForm.addEventListener('submit', async (event) => {
        event.preventDefault();
        const email = document.getElementById('signup-email').value;
        const password = document.getElementById('signup-password').value;

        try {
            const response = await fetch('/users', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ email, password }),
            });

            if (response.ok) {
                displayMessage('Signup successful! Please log in.', 'success');
                signupForm.reset();
            } else {
                const errorData = await response.json();
                displayMessage(`Signup failed: ${errorData.detail}`, 'error');
            }
        } catch (error) {
            displayMessage('An error occurred. Please try again.', 'error');
        }
    });

    // --- Login Form Handler ---
    loginForm.addEventListener('submit', async (event) => {
        event.preventDefault();
        const email = document.getElementById('login-email').value;
        const password = document.getElementById('login-password').value;

        // FastAPI's OAuth2 expects form data, not JSON
        const formData = new URLSearchParams();
        formData.append('username', email);
        formData.append('password', password);

        try {
            const response = await fetch('/token', {
                method: 'POST',
                headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                body: formData,
            });

            if (response.ok) {
                const data = await response.json();
                // Save the token and redirect to the dashboard
                localStorage.setItem('accessToken', data.access_token);
                window.location.href = '/dashboard.html';
            } else {
                const errorData = await response.json();
                displayMessage(`Login failed: ${errorData.detail}`, 'error');
            }
        } catch (error) {
            displayMessage('An error occurred. Please try again.', 'error');
        }
    });
});