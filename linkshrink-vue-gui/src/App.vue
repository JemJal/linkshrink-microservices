<script setup>
// This imports the special component from vue-router that
// acts as a placeholder to render our page "views"
import { RouterView } from 'vue-router'

// This imports our simple navigation bar component
import NavBar from './components/NavBar.vue'
</script>

<template>
  <!-- Render the navigation bar at the top of every page -->
  <NavBar />
  
  <main>
    <!-- Render the current page's component here -->
    <RouterView />
  </main>
</template>