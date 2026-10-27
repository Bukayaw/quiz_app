const express = require("express");
const cors = require("cors");

const { poolPromise } = require("./db");

require("dotenv").config();

const app = express();

app.use(cors());
app.use(express.json());


// Test server
app.get("/", (req, res) => {
    res.json({
        message: "Quiz App Server is running"
    });
});


// Test SQL Server connection
app.get("/test-db", async (req, res) => {

    try {

        const pool = await poolPromise;

        const result = await pool
            .request()
            .query("SELECT GETDATE() AS current_time");

        res.json({
            message: "SQL Server connected",
            time: result.recordset[0].current_time
        });

    } catch (error) {

        console.error(error);

        res.status(500).json({
            message: "Database connection failed"
        });
    }
});


const PORT = process.env.PORT || 3000;

app.listen(PORT, () => {
    console.log(
        `Server running on http://localhost:${PORT}`
    );
});