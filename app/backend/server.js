const express = require("express");
const cors = require("cors");
const { Pool } = require("pg");

const app = express();
const port = process.env.PORT || 5000;

// Enable CORS for cross-origin requests from the frontend
app.use(cors());
app.use(express.json());

// Database connection pool using environment variables
const pool = new Pool({
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME || "appdb",
  port: process.env.DB_PORT || 5432,
  // Required for AWS RDS connections:
  ssl:
    process.env.NODE_ENV === "production"
      ? { rejectUnauthorized: false }
      : false,
});

// Health check endpoint for container orchestrators (ECS / K8s)
app.get("/health", (req, res) => {
  res.status(200).json({ status: "healthy", timestamp: new Date() });
});

// Primary API endpoint called by the frontend
app.get("/api/data", async (req, res) => {
  try {
    const result = await pool.query("SELECT NOW()");
    res.json({
      message: "Hello from the Backend API!",
      db_time: result.rows[0].now,
    });
  } catch (err) {
    console.error("Database query error:", err.message);
    res.status(500).json({
      error: "Database connection failed",
      details: err.message,
    });
  }
});

app.listen(port, () => {
  console.log(`Backend API running on port ${port}`);
});
