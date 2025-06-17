document.addEventListener('DOMContentLoaded', () => {
    // --- Authentication Check ---
    // This is our "Auth Guard". If there's no token, redirect to the login page.
    const token = localStorage.getItem('accessToken');
    if (!token) {
        window.location.href = '/index.html';
        return; // Stop executing script
    }

    // --- DOM Elements ---
    const linkList = document.getElementById('link-list');
    const createLinkForm = document.getElementById('create-link-form');
    const messageArea = document.getElementById('message-area');
    const logoutButton = document.getElementById('logout-button');

    // --- Helper to display messages ---
    const displayMessage = (message, type) => {
        messageArea.textContent = message;
        messageArea.className = type;
    };

    // --- Function to fetch and display user's links ---
    const fetchLinks = async () => {
        try {
            const response = await fetch('/links', {
                method: 'GET',
                headers: { 'Authorization': `Bearer ${token}` }
            });

            if (!response.ok) {
                // If token is expired or invalid, the API will return 401
                if (response.status === 401) {
                    localStorage.removeItem('accessToken');
                    window.location.href = '/index.html';
                }
                throw new Error('Could not fetch links.');
            }

            const links = await response.json();
            linkList.innerHTML = ''; // Clear the list before rendering
            links.forEach(link => {
                const li = document.createElement('li');
                li.innerHTML = `
                    <span class="short-url">${link.short_url}</span>
                    <span class="original-url">${link.original_url}</span>
                `;
                linkList.appendChild(li);
            });

        } catch (error) {
            displayMessage(error.message, 'error');
        }
    };

    // --- Form handler for creating a new link ---
    createLinkForm.addEventListener('submit', async (event) => {
        event.preventDefault();
        const originalUrl = document.getElementById('original-url').value;

        try {
            const response = await fetch('/links', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Authorization': `Bearer ${token}`
                },
                body: JSON.stringify({ original_url: originalUrl })
            });

            if (response.ok) {
                displayMessage('Link created successfully!', 'success');
                createLinkForm.reset();
                fetchLinks(); // Refresh the list to show the new link
            } else {
                const errorData = await response.json();
                displayMessage(`Error: ${errorData.detail}`, 'error');
            }
        } catch (error) {
            displayMessage('An error occurred.', 'error');
        }
    });

    // --- Logout button handler ---
    logoutButton.addEventListener('click', () => {
        localStorage.removeItem('accessToken');
        window.location.href = '/index.html';
    });

    // --- Initial Load ---
    // Fetch the links as soon as the page loads
    fetchLinks();
});