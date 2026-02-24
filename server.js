const express = require("express");
const app = express();
const PORT = process.env.PORT || 3000;

app.get("/", (req, res) => {
  res.json({
    title: "Hello Docker !",
    message: "Le endpoint / fonctionne correctement !",
  });
});

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});

// Gère l'arrêt Ctrl+C
process.on('SIGINT', () => {
  console.log('Shutting down...');
  process.exit(0);
});

// Gère l'arrêt docker stop
process.on('SIGTERM', () => {
  console.log('Shutting down...');
  process.exit(0);
});

