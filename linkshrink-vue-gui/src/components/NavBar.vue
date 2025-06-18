<template>
  <header>
    <nav>
      <router-link to="/login">Login</router-link>
      <router-link to="/dashboard">Dashboard</router-link>
    </nav>
  </header>
</template>

<style scoped>
header {
  background-color: #f8f9fa;
  padding: 1rem;
  border-bottom: 1px solid #dee2e6;
  margin-bottom: 2rem;
}
nav {
  display: flex;
  gap: 1rem;
}
</style>