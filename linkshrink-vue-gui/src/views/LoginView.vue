<script setup>
import { ref } from 'vue'
import { useRouter } from 'vue-router'

// This gives us access to the Vue router instance
const router = useRouter()

// --- Refs for Signup Form ---
// 'ref' creates a reactive variable. Vue will automatically keep this
// in sync with the input field in the template.
const signupEmail = ref('')
const signupPassword = ref('')

// --- Refs for Login Form ---
const loginEmail = ref('')
const loginPassword = ref('')

// --- Ref for displaying messages ---
const message = ref('')
const messageType = ref('') // 'success' or 'error'

// --- Signup Logic ---
const handleSignup = async () => {
  try {
    const response = await fetch('/users', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: signupEmail.value,
        password: signupPassword.value
      })
    })

    if (response.ok) {
      message.value = 'Signup successful! Please log in.'
      messageType.value = 'success'
      signupEmail.value = '' // Clear the form
      signupPassword.value = ''
    } else {
      const errorData = await response.json()
      throw new Error(errorData.detail || 'Signup failed')
    }
  } catch (error) {
    message.value = error.message
    messageType.value = 'error'
  }
}

// --- Login Logic ---
const handleLogin = async () => {
  // Our backend /token endpoint expects "form urlencoded" data, not JSON.
  const formData = new URLSearchParams()
  formData.append('username', loginEmail.value)
  formData.append('password', loginPassword.value)

  try {
    const response = await fetch('/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: formData
    })

    if (response.ok) {
      const data = await response.json()
      // On successful login, save the token to the browser's local storage
      localStorage.setItem('accessToken', data.access_token)
      // And then programmatically navigate to the dashboard page
      router.push('/dashboard')
    } else {
      const errorData = await response.json()
      throw new Error(errorData.detail || 'Login failed')
    }
  } catch (error) {
    message.value = error.message
    messageType.value = 'error'
  }
}
</script>

<template>
  <div class="view-container auth-page">
    <h1>LinkShrink</h1>
    <p>A modern URL shortener built with Vue.js and Microservices</p>

    <!-- Message Area -->
    <div v-if="message" class="message-area" :class="messageType">
      {{ message }}
    </div>

    <div class="form-container">
      <!-- Sign Up Form -->
      <!-- @submit.prevent tells Vue to run our 'handleSignup' function
           instead of doing a normal browser form submission. -->
      <form @submit.prevent="handleSignup">
        <h2>Sign Up</h2>
        <!-- v-model creates a two-way binding between this input
             and our 'signupEmail' variable in the script. -->
        <input type="email" v-model="signupEmail" placeholder="Email" required />
        <input type="password" v-model="signupPassword" placeholder="Password" required />
        <button type="submit">Sign Up</button>
      </form>

      <!-- Login Form -->
      <form @submit.prevent="handleLogin">
        <h2>Login</h2>
        <input type="email" v-model="loginEmail" placeholder="Email" required />
        <input type="password" v-model="loginPassword" placeholder="Password" required />
        <button type="submit">Login</button>
      </form>
    </div>
  </div>
</template>

<style scoped>
/* 'scoped' means these styles only apply to this component */
.auth-page {
  text-align: center;
}

.form-container {
  display: flex;
  justify-content: center;
  gap: 3rem;
  margin-top: 2rem;
}

form {
  display: flex;
  flex-direction: column;
  width: 300px;
  background: white;
  padding: 2rem;
  border-radius: 8px;
  box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
}

h2 {
  margin-top: 0;
  margin-bottom: 1.5rem;
}

input {
  padding: 0.75rem;
  margin-bottom: 1rem;
  border: 1px solid #ddd;
  border-radius: 4px;
  font-size: 1rem;
}

button {
  padding: 0.75rem;
  border: none;
  border-radius: 4px;
  background-color: #007bff;
  color: white;
  font-size: 1rem;
  cursor: pointer;
  transition: background-color 0.2s;
}

button:hover {
  background-color: #0056b3;
}

.message-area {
  margin: 1rem auto;
  padding: 1rem;
  border-radius: 4px;
  max-width: 650px;
}
.success {
  background-color: #d4edda;
  color: #155724;
}
.error {
  background-color: #f8d7da;
  color: #721c24;
}
</style>