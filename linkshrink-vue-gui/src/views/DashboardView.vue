<script setup>
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'

// --- Setup ---
const router = useRouter()
const token = localStorage.getItem('accessToken')

// --- Reactive State ---
const links = ref([])
const newUrl = ref('')
const customCode = ref('') // This was already here, which is great!
const message = ref('')
const messageType = ref('')

// --- Auth Guard & Data Fetching ---
onMounted(() => {
  if (!token) {
    router.push('/login')
    return
  }
  fetchLinks()
})

// --- API Functions ---
const fetchLinks = async () => {
  try {
    const response = await fetch('/links', {
      method: 'GET',
      headers: { Authorization: `Bearer ${token}` }
    })
    if (!response.ok) {
      if (response.status === 401) {
        handleLogout()
      }
      throw new Error('Could not fetch links.')
    }
    links.value = await response.json()
  } catch (error) {
    console.error(error)
  }
}

// --- UPDATED: The createLink function ---
const createLink = async () => {
  // Clear previous messages
  message.value = ''
  
  try {
    const payload = {
      original_url: newUrl.value
    };
    
    // Only include the custom code if the user actually typed something
    if (customCode.value.trim()) {
      payload.custom_short_code = customCode.value.trim();
    }

    const response = await fetch('/links', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${token}`
      },
      body: JSON.stringify(payload)
    })

    if (response.ok) {
      message.value = 'Link created successfully!'
      messageType.value = 'success'
      newUrl.value = '' // Clear the form
      customCode.value = '' // Clear the custom code input too
      await fetchLinks() // Refresh the list
    } else {
      const errorData = await response.json()
      throw new Error(errorData.detail || 'Failed to create link.')
    }
  } catch (error) {
    message.value = error.message
    messageType.value = 'error'
  }
}

// --- Logout Logic ---
const handleLogout = () => {
  localStorage.removeItem('accessToken')
  router.push('/login')
}
</script>

<template>
  <div class="view-container dashboard-page">
    <header>
      <h1>Dashboard</h1>
      <button @click="handleLogout" class="logout-button">Logout</button>
    </header>

    <div v-if="message" class="message-area" :class="messageType">
      {{ message }}
    </div>

    <!-- Create New Link Form -->
    <div class="card">
      <h2>Create New Link</h2>
      <!-- UPDATED: Added new CSS classes to the inputs for better styling -->
      <form @submit.prevent="createLink" class="create-form">
        <input type="url" class="url-input" v-model="newUrl" placeholder="https://your-long-url.com" required />
        <input type="text" class="code-input" v-model="customCode" placeholder="custom-code (optional)" />
        <button type="submit">Shrink It!</button>
      </form>
    </div>

    <!-- User's Link List -->
    <div class="card">
      <h2>Your Links</h2>
      <ul v-if="links.length > 0" class="link-list">
        <li v-for="link in links" :key="link.short_url">
          <!-- The link now correctly points to the redirectable URL -->
          <a :href="link.short_url" target="_blank" class="short-url">{{ link.short_url }}</a>
          <span class="original-url">{{ link.original_url }}</span>
        </li>
      </ul>
      <p v-else>You haven't created any links yet.</p>
    </div>
  </div>
</template>

<style scoped>
.dashboard-page {
  max-width: 800px;
}
header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  border-bottom: 1px solid #eee;
  padding-bottom: 1rem;
  margin-bottom: 2rem;
}
header h1 {
  margin: 0;
}
.logout-button {
  padding: 0.5rem 1rem;
  background-color: #dc3545;
  color: white;
  border: none;
  border-radius: 4px;
  cursor: pointer;
}
.card {
  background: white;
  padding: 1.5rem;
  border-radius: 8px;
  box-shadow: 0 4px 6px rgba(0, 0, 0, 0.05);
  margin-bottom: 2rem;
}

/* --- UPDATED: Form styles for better layout --- */
.create-form {
  display: grid;
  grid-template-columns: 1fr auto auto;
  gap: 0.5rem;
  align-items: center;
}
.create-form input {
  padding: 0.75rem;
  border: 1px solid #ddd;
  border-radius: 4px;
  font-size: 1rem;
}
.code-input {
  width: 180px;
}
.create-form button {
  padding: 0.75rem 1.5rem;
  border: none;
  border-radius: 4px;
  background-color: #007bff;
  color: white;
  font-size: 1rem;
  cursor: pointer;
}

.link-list {
  list-style-type: none;
  padding: 0;
}
.link-list li {
  padding: 1rem;
  border-bottom: 1px solid #eee;
}
.link-list li:last-child {
  border-bottom: none;
}
.short-url {
  font-weight: bold;
  color: #007bff;
  text-decoration: none;
}
.original-url {
  display: block;
  color: #6c757d;
  font-size: 0.9em;
  margin-top: 0.25rem;
  word-break: break-all;
}
.message-area {
  margin-bottom: 1rem;
  padding: 1rem;
  border-radius: 4px;
}
.success { background-color: #d4edda; color: #155724; }
.error { background-color: #f8d7da; color: #721c24; }
</style>