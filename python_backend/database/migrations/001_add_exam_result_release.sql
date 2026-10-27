IF COL_LENGTH('dbo.ExamResults', 'IsReleased') IS NULL
BEGIN
    ALTER TABLE dbo.ExamResults
    ADD IsReleased BIT NOT NULL
        CONSTRAINT DF_ExamResults_IsReleased DEFAULT (0) WITH VALUES;
END;
