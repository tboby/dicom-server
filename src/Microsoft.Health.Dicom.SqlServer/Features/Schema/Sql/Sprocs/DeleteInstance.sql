/***************************************************************************************/
-- STORED PROCEDURE
--     DeleteInstance
--
-- DESCRIPTION
--     Removes the specified instance(s) and places them in the DeletedInstance table for later removal
--
-- PARAMETERS
--     @cleanupAfter
--         * The date time offset that the instance can be cleaned up.
--     @createdStatus
--         * Status value representing the created state.
--     @studyInstanceUid
--         * The study instance UID.
--     @seriesInstanceUid
--         * The series instance UID.
--     @sopInstanceUid
--         * The SOP instance UID.
/***************************************************************************************/
CREATE OR ALTER PROCEDURE dbo.DeleteInstance
    @cleanupAfter       DATETIMEOFFSET(0),
    @createdStatus      TINYINT,
    @studyInstanceUid   VARCHAR(64),
    @seriesInstanceUid  VARCHAR(64) = null,
    @sopInstanceUid     VARCHAR(64) = null
AS
    SET NOCOUNT ON
    SET XACT_ABORT ON

    BEGIN TRANSACTION

    DECLARE @deletedInstances AS TABLE
        (StudyInstanceUid VARCHAR(64),
            SeriesInstanceUid VARCHAR(64),
            SopInstanceUid VARCHAR(64),
            Status TINYINT,
            Watermark BIGINT)

    DECLARE @studyKey BIGINT
    DECLARE @seriesKey BIGINT
    DECLARE @instanceKey BIGINT
    DECLARE @deletedDate DATETIME2 = SYSUTCDATETIME()

    -- Get the study, series and instance PK
    SELECT  @studyKey = StudyKey,
    @seriesKey = CASE @seriesInstanceUid WHEN NULL THEN NULL ELSE SeriesKey END,
    @instanceKey = CASE @sopInstanceUid WHEN NULL THEN NULL ELSE InstanceKey END
    FROM    dbo.Instance
    WHERE   StudyInstanceUid = @studyInstanceUid
    AND     SeriesInstanceUid = ISNULL(@seriesInstanceUid, SeriesInstanceUid)
    AND     SopInstanceUid = ISNULL(@sopInstanceUid, SopInstanceUid)

    -- Delete the instance and insert the details into DeletedInstance and ChangeFeed
    DELETE  dbo.Instance
        OUTPUT deleted.StudyInstanceUid, deleted.SeriesInstanceUid, deleted.SopInstanceUid, deleted.Status, deleted.Watermark
        INTO @deletedInstances
    WHERE   StudyInstanceUid = @studyInstanceUid
    AND     SeriesInstanceUid = ISNULL(@seriesInstanceUid, SeriesInstanceUid)
    AND     SopInstanceUid = ISNULL(@sopInstanceUid, SopInstanceUid)

    IF @@ROWCOUNT = 0
        THROW 50404, 'Instance not found', 1

    -- Deleting tag errors
    DECLARE @deletedTags AS TABLE
    (
        TagKey BIGINT
    )
    DELETE XQTE
        OUTPUT deleted.TagKey
        INTO @deletedTags
    FROM dbo.ExtendedQueryTagError as XQTE
    INNER JOIN @deletedInstances as d
    ON XQTE.Watermark = d.Watermark

    -- Update error count
    IF EXISTS (SELECT * FROM @deletedTags)
    BEGIN
        DECLARE @deletedTagCounts AS TABLE
        (
            TagKey BIGINT,
            ErrorCount INT
        )

        -- Calculate error count
        INSERT INTO @deletedTagCounts
            (TagKey, ErrorCount)
        SELECT TagKey, COUNT(1)
        FROM @deletedTags
        GROUP BY TagKey

        UPDATE XQT
        SET XQT.ErrorCount = XQT.ErrorCount - DTC.ErrorCount
        FROM dbo.ExtendedQueryTag AS XQT
        INNER JOIN @deletedTagCounts AS DTC
        ON XQT.TagKey = DTC.TagKey
    END

    -- Deleting indexed instance tags
    DELETE
    FROM    dbo.ExtendedQueryTagString
    WHERE   StudyKey = @studyKey
    AND     SeriesKey = ISNULL(@seriesKey, SeriesKey)
    AND     InstanceKey = ISNULL(@instanceKey, InstanceKey)

    DELETE
    FROM    dbo.ExtendedQueryTagLong
    WHERE   StudyKey = @studyKey
    AND     SeriesKey = ISNULL(@seriesKey, SeriesKey)
    AND     InstanceKey = ISNULL(@instanceKey, InstanceKey)

    DELETE
    FROM    dbo.ExtendedQueryTagDouble
    WHERE   StudyKey = @studyKey
    AND     SeriesKey = ISNULL(@seriesKey, SeriesKey)
    AND     InstanceKey = ISNULL(@instanceKey, InstanceKey)

    DELETE
    FROM    dbo.ExtendedQueryTagDateTime
    WHERE   StudyKey = @studyKey
    AND     SeriesKey = ISNULL(@seriesKey, SeriesKey)
    AND     InstanceKey = ISNULL(@instanceKey, InstanceKey)

    DELETE
    FROM    dbo.ExtendedQueryTagPersonName
    WHERE   StudyKey = @studyKey
    AND     SeriesKey = ISNULL(@seriesKey, SeriesKey)
    AND     InstanceKey = ISNULL(@instanceKey, InstanceKey)

    INSERT INTO dbo.DeletedInstance
    (StudyInstanceUid, SeriesInstanceUid, SopInstanceUid, Watermark, DeletedDateTime, RetryCount, CleanupAfter)
    SELECT StudyInstanceUid, SeriesInstanceUid, SopInstanceUid, Watermark, @deletedDate, 0 , @cleanupAfter
    FROM @deletedInstances

    INSERT INTO dbo.ChangeFeed
    (TimeStamp, Action, StudyInstanceUid, SeriesInstanceUid, SopInstanceUid, OriginalWatermark)
    SELECT @deletedDate, 1, StudyInstanceUid, SeriesInstanceUid, SopInstanceUid, Watermark
    FROM @deletedInstances
    WHERE Status = @createdStatus

    UPDATE cf
    SET cf.CurrentWatermark = NULL
    FROM dbo.ChangeFeed cf WITH(FORCESEEK)
    JOIN @deletedInstances d
    ON cf.StudyInstanceUid = d.StudyInstanceUid
        AND cf.SeriesInstanceUid = d.SeriesInstanceUid
        AND cf.SopInstanceUid = d.SopInstanceUid

    -- If this is the last instance for a series, remove the series
    IF NOT EXISTS ( SELECT  *
                    FROM    dbo.Instance WITH(HOLDLOCK, UPDLOCK)
                    WHERE   StudyKey = @studyKey
                    AND     SeriesInstanceUid = ISNULL(@seriesInstanceUid, SeriesInstanceUid))
    BEGIN
        DELETE
        FROM    dbo.Series
        WHERE   Studykey = @studyKey
        AND     SeriesInstanceUid = ISNULL(@seriesInstanceUid, SeriesInstanceUid)

        -- Deleting indexed series tags
        DELETE
        FROM    dbo.ExtendedQueryTagString
        WHERE   StudyKey = @studyKey
        AND     SeriesKey = ISNULL(@seriesKey, SeriesKey)

        DELETE
        FROM    dbo.ExtendedQueryTagLong
        WHERE   StudyKey = @studyKey
        AND     SeriesKey = ISNULL(@seriesKey, SeriesKey)

        DELETE
        FROM    dbo.ExtendedQueryTagDouble
        WHERE   StudyKey = @studyKey
        AND     SeriesKey = ISNULL(@seriesKey, SeriesKey)

        DELETE
        FROM    dbo.ExtendedQueryTagDateTime
        WHERE   StudyKey = @studyKey
        AND     SeriesKey = ISNULL(@seriesKey, SeriesKey)

        DELETE
        FROM    dbo.ExtendedQueryTagPersonName
        WHERE   StudyKey = @studyKey
        AND     SeriesKey = ISNULL(@seriesKey, SeriesKey)
    END

    -- If we've removing the series, see if it's the last for a study and if so, remove the study
    IF NOT EXISTS ( SELECT  *
                    FROM    dbo.Series WITH(HOLDLOCK, UPDLOCK)
                    WHERE   Studykey = @studyKey)
    BEGIN
        DELETE
        FROM    dbo.Study
        WHERE   Studykey = @studyKey

        -- Deleting indexed study tags
        DELETE
        FROM    dbo.ExtendedQueryTagString
        WHERE   StudyKey = @studyKey

        DELETE
        FROM    dbo.ExtendedQueryTagLong
        WHERE   StudyKey = @studyKey

        DELETE
        FROM    dbo.ExtendedQueryTagDouble
        WHERE   StudyKey = @studyKey

        DELETE
        FROM    dbo.ExtendedQueryTagDateTime
        WHERE   StudyKey = @studyKey

        DELETE
        FROM    dbo.ExtendedQueryTagPersonName
        WHERE   StudyKey = @studyKey
    END

    COMMIT TRANSACTION
