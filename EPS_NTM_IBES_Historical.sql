/*
    @AUTHOR :   PRAVEEN KUMAR V
    @DESC   :   THIS QUERY WILL RETURN HISTORICAL NTM EPS VALUES. BPN CURRENCY HAS BEEN CONVERTED TO GBP.

   
    @EDITS  :   4/18/2018: UPDATED QUERY LOGIC TO DEAL WITH PSEDUO NULLS (-99999) IN IB[B/G]SESTL* TABLES. UPDATED QUERY TO REMOVE ISNULL LOGIC. CALCULATION WILL NOW RESULT IN NULL IF FY0 OR FY1/FY2/FY3 ARE NULL AND USED IN THE CALCULATION
                5/14/2018: ADDED BPN TO GBP CURRENCY CONVERSION FOR UNITED STATES TABLES
                5/18/2018: ADDED COMMENTS & VERSION CONTROL
                5/22/2018: REMOVED UNNEEDED ORDER BYS AND GROUP BYS, CLEANED UP SEMICOLONS IN DECLARES, AND REMOVED COMPANY FILTERS
                5/22/2018: ADDED STARTDATE, ENDDATE AND COUNTRYOFEXCHANGE
                7/03/2018: CHANGED JOIN TO LEFT JOIN FOR E2 & E3 TABLE
		7/22/2018: MODIFIED QUERY TO REPLICATE DFO FUNCTIONALITY
	       10/22/2018: ADDED P/C CONDITION & BASIS FLAG
*/
   
DECLARE @STARTDATE SMALLDATETIME = '2010-01-01'; --@STARTDATE
DECLARE @ENDDATE SMALLDATETIME = GETDATE();   --@ENDDATE
   
---- IBES MAPPING
WITH IBESV1MAPPING AS (SELECT *,1 AS REGCODE FROM SECMAPX WHERE VENTYPE = 42 UNION ALL SELECT *,6 AS REGCODE FROM GSECMAPX WHERE VENTYPE = 2)


---- RETRIEVES MOST RECENT PRIMARY BASIS AND HISTORICAL PRIMARY BASIS
, PRIMARYBASIS AS (
	SELECT  B.CODE AS CODE_QFS
	, B.PRIMARYFLAG  AS PRIMARYFLAGQFS 
	, B.ENTRYDATE  AS DATE_QFS
	, A.CODE AS CODE_HIST
	, A.DATE_ AS DATE_HIST
	, A.CANCURR AS CANCURR_HIST
	, CASE WHEN (B.PRIMARYFLAG = 'P' AND A.CANCURR IN ('C','')) OR (B.PRIMARYFLAG = 'C' AND A.CANCURR= 'P') THEN 2 ELSE 1 END AS HISTORICALBASISFLAG
	 FROM IBGSHIST3 A 
     OUTER APPLY (SELECT TOP 1 B.CODE, B.PRIMARYFLAG, B.ENTRYDATE
                           FROM IBGQPRIMMSR B 
                           WHERE A.CODE=B.CODE 
                           ORDER BY B.ENTRYDATE DESC) B)

---- IBES SUMMARY ESTIMATE DATA TO GET FY1, FY2 & FY3 MEAN DATA
, USESTDATA AS (SELECT A.CODE,A.MEASURE,A.ESTDATE, A.PERDATE,A.PERIOD, A.PERTYPE
                    ,CASE WHEN C.CURRENCY_= 'BPN' THEN (NULLIF(A.MEAN,-99999)/ISNULL(B.SPLITFACTOR,1))/100 ELSE (NULLIF(A.MEAN,-99999)/ISNULL(B.SPLITFACTOR,1)) END AS MEAN -- CASE STATEMENT TO CONVERT PENCE TO POUNDS 
                    ,CASE WHEN C.CURRENCY_ = 'BPN' THEN 'GBP' ELSE C.CURRENCY_ END AS QAD_CURRENCY_
					--,D.CURRENCY_ AS DFO_CURRENCY_ 
                FROM IBESESTL1 A 
                LEFT JOIN IBQSPL B  
                    ON  B.CODE=A.CODE 
                    AND B.ENTRYDATE>(SELECT MAX(DATE_) FROM IBESADJ)--ONLY SPLITS ENTERED SINCE MONTHLY REFRESH 
                OUTER APPLY (SELECT TOP 1 C.CODE, C.CURRENCY_ FROM  IBESCUR C WHERE C.CODE=A.CODE AND C.DATE_ <= A.ESTDATE ORDER BY C.DATE_ DESC ) C
				--OUTER APPLY (SELECT TOP 1 D.CODE, D.CURRENCY_ FROM IBESCUR D WHERE D.CODE=A.CODE ORDER BY D.DATE_ DESC ) D
                WHERE A.ESTDATE >= @STARTDATE AND A.ESTDATE < @ENDDATE AND A.MEASURE=8 AND A.PERTYPE=1)
  
---- IBES GLOBAL SUMMARY ESTIMATE DATA          
, GESTDATA AS (SELECT A.CODE,A.MEASURE,A.ESTDATE, A.PERDATE,A.PERIOD, A.PERTYPE
                ,CASE WHEN C.CURRENCY_= 'BPN' THEN (NULLIF(A.MEAN,-99999)/ISNULL(B.SPLITFACTOR,1))/100 ELSE (NULLIF(A.MEAN,-99999)/ISNULL(B.SPLITFACTOR,1)) END AS MEAN -- CASE STATEMENT TO CONVERT PENCE TO POUNDS 
                ,CASE WHEN C.CURRENCY_ = 'BPN' THEN 'GBP' ELSE C.CURRENCY_ END AS QAD_CURRENCY_
				--,D.CURRENCY_ AS DFO_CURRENCY_ 
            FROM (SELECT *, '1' AS HISTORICALBASISFLAG FROM IBGSESTL1 UNION SELECT *, '2' AS HISTORICALBASISFLAG FROM IBGS2NDESTL1) A
			OUTER APPLY (SELECT TOP 1 * --  A1.CODE_HIST, A1.HISTORICALBASISFLAG
			FROM  PRIMARYBASIS A1
			WHERE A.CODE=A1.CODE_HIST 
				AND A.HISTORICALBASISFLAG=A1.HISTORICALBASISFLAG
				AND A1.DATE_HIST <= A.ESTDATE 
				ORDER BY A1.DATE_HIST DESC ) A1
            LEFT JOIN IBGQSPL B 
                ON  B.CODE=A.CODE 
                AND B.ENTRYDATE>(SELECT MAX(DATE_) FROM IBGSADJ )--ONLY SPLITS ENTERED SINCE MONTHLY REFRESH 
            OUTER APPLY (SELECT TOP 1 C.CODE, C.CURRENCY_ FROM  IBGSCUR C WHERE C.CODE=A.CODE AND C.DATE_ <= A.ESTDATE ORDER BY C.DATE_ DESC ) C
			--OUTER APPLY (SELECT TOP 1 D.CODE, D.CURRENCY_ FROM IBGSCUR D WHERE D.CODE=A.CODE ORDER BY D.DATE_ DESC ) D
            WHERE A.ESTDATE >= @STARTDATE AND A.ESTDATE < @ENDDATE AND A.MEASURE=8 AND A.PERTYPE=1 AND A.HISTORICALBASISFLAG=A1.HISTORICALBASISFLAG)
  
, ESTDATA AS (SELECT *,1 AS REGCODE FROM USESTDATA  UNION ALL SELECT *,6 AS REGCODE FROM GESTDATA)
  
, FWD_12 AS (   SELECT
                U.COUNTRYOFEXCHANGE,
                U.SECCODE, 
                U.REGCODE,
                U.ID,
                U.IDENTIFIER, 
                I.ITICKER,
                I.CODE,
                E1.QAD_CURRENCY_,
				--E1.DFO_CURRENCY_,
                E1.ESTDATE, 
                E1.PERDATE AS FY1_PERDATE, 
                ROUND(E1.MEAN,2)  AS FY1_EPS, 
                ROUND(E2.MEAN,2)  AS FY2_EPS, 
                ROUND(E3.MEAN,2)  AS FY3_EPS,
				PC.PRIMARYFLAGQFS,
				PC.CANCURR_HIST,
   
      CASE  WHEN (YEAR(E1.PERDATE) < YEAR(E1.ESTDATE) OR (YEAR(E1.PERDATE) = YEAR(E1.ESTDATE) AND MONTH(E1.PERDATE) < MONTH(E1.ESTDATE)))
            THEN  
                CASE WHEN (MONTH(E1.PERDATE) = 12) THEN E2.MEAN * (12 - MONTH(E1.ESTDATE))/12.0 + E3.MEAN * MONTH(E1.ESTDATE)/12.0
                     WHEN ((MONTH(E1.PERDATE) <> 12) AND (MONTH(E1.ESTDATE) > MONTH(E1.PERDATE))) THEN E2.MEAN * (12 - (MONTH(E1.ESTDATE) - MONTH(E1.PERDATE)))/12.0 + E3.MEAN * (MONTH(E1.ESTDATE) - MONTH(E1.PERDATE))/12.0
                ELSE E2.MEAN * (MONTH(E1.PERDATE) - MONTH(E1.ESTDATE))/12.0 + E3.MEAN * (12 - (MONTH(E1.PERDATE) - MONTH(E1.ESTDATE)))/12.0
            END
            ELSE  
                CASE WHEN (MONTH(E1.PERDATE) = 12) THEN E1.MEAN * (12 - MONTH(E1.ESTDATE))/12.0 + E2.MEAN * MONTH(E1.ESTDATE)/12.0
                     WHEN (MONTH(E1.PERDATE) <> 12 AND MONTH(E1.ESTDATE) > MONTH(E1.PERDATE)) THEN E1.MEAN * (12 - (MONTH(E1.ESTDATE) - MONTH(E1.PERDATE)))/12.0 + E2.MEAN * (MONTH(E1.ESTDATE) - MONTH(E1.PERDATE))/12.0
                     ELSE E1.MEAN * (MONTH(E1.PERDATE) - MONTH(E1.ESTDATE))/12.0 + E2.MEAN * (12 - (MONTH(E1.PERDATE) - MONTH(E1.ESTDATE)))/12.0
            END
     END AS EPS_NTM
   
FROM SUPPORT_DB.DBO.COGNITIVESCALEUNIVERSE U
LEFT JOIN IBESV1MAPPING P
    ON  P.SECCODE = U.SECCODE
    AND P.REGCODE = U.REGCODE
    AND P.EXCHANGE = U.EXCHANGE
    AND P.[RANK] = (SELECT MIN([RANK]) FROM IBESV1MAPPING WHERE SECCODE = P.SECCODE AND REGCODE = P.REGCODE AND EXCHANGE = P.EXCHANGE)
LEFT JOIN (SELECT *,1 AS REGCODE FROM IBESINFO3 UNION ALL SELECT *,6 AS REGCODE FROM IBGSINFO3) I
    ON  I.CODE = P.VENCODE
    AND I.REGCODE = CASE P.EXCHANGE WHEN 1 THEN 1 WHEN 2 THEN 6 WHEN 0 THEN 6 END
LEFT JOIN ESTDATA E1 
    ON E1.CODE=I.CODE 
    AND E1.REGCODE = I.REGCODE
	AND E1.PERIOD = 1
LEFT JOIN ESTDATA E2
    ON E2.CODE=I.CODE 
    AND E2.REGCODE = I.REGCODE
    AND E1.ESTDATE=E2.ESTDATE
	AND E2.PERIOD = 2
LEFT JOIN ESTDATA E3
    ON E3.CODE=I.CODE 
    AND E3.REGCODE = I.REGCODE
    AND E1.ESTDATE=E3.ESTDATE
	AND E3.PERIOD = 3
LEFT JOIN PRIMARYBASIS PC
	ON I.CODE = ISNULL(PC.CODE_QFS,PC.CODE_HIST)
	--AND PC.DATE_QFS = (SELECT TOP 1 DATE_QFS FROM PRIMARYBASIS WHERE CODE_QFS = PC.CODE_QFS ORDER BY DATE_QFS DESC)
	AND PC.DATE_HIST = (SELECT TOP 1 DATE_HIST FROM PRIMARYBASIS WHERE CODE_HIST = PC.CODE_HIST ORDER BY DATE_HIST DESC)

--WHERE U.COUNTRYOFEXCHANGE IN ('UNITED KINGDOM') --@COUNTRIES
)
   
  
SELECT	F.COUNTRYOFEXCHANGE
, F.ID
--, F.IDENTIFIER
--, F.ITICKER
, F.CODE
, F.QAD_CURRENCY_ 
--, F.DFO_CURRENCY_
, F.ESTDATE
, F.FY1_PERDATE
, FY1_EPS
, FY2_EPS
, FY3_EPS
, ROUND(F.EPS_NTM,2) AS QAD_EPS_NTM
, CASE WHEN REGCODE = 6 THEN ISNULL(PRIMARYFLAGQFS,(CASE WHEN CANCURR_HIST = ' ' THEN 'C' ELSE CANCURR_HIST END)) 
		WHEN REGCODE = 1 THEN 'C' ELSE 'NULL' END AS BASIS

		--CASE WHEN F.QAD_CURRENCY_ = F.DFO_CURRENCY_ THEN ROUND(F.EPS_NTM,2)
		--	 WHEN F.QAD_CURRENCY_ = 'GBP' AND F.DFO_CURRENCY_ = 'BPN' THEN ROUND(F.EPS_NTM*100,2)
		--	  ELSE ROUND(F.EPS_NTM*(TGTFX.MIDRATE/GBPFX.MIDRATE),2)	
		--END AS DFO_EPS_NTM
FROM FWD_12 F
--LEFT JOIN DS2FXCODE GBP
--	ON F.QAD_CURRENCY_ = GBP.FROMCURRCODE
--	AND GBP.TOCURRCODE = 'GBP'
--	AND GBP.RATETYPECODE = 'SPOT'
--LEFT JOIN DS2FXRATE GBPFX
--	ON GBP.EXRATEINTCODE = GBPFX.EXRATEINTCODE
--	AND GBPFX.EXRATEDATE = (SELECT MAX(EXRATEDATE) FROM DS2FXRATE WHERE EXRATEINTCODE = GBPFX.EXRATEINTCODE AND EXRATEDATE <= F.ESTDATE)
--LEFT JOIN DS2FXCODE TGT
--	ON F.DFO_CURRENCY_ = TGT.FROMCURRCODE
--	AND TGT.TOCURRCODE = GBP.TOCURRCODE
--    AND TGT.RATETYPECODE = GBP.RATETYPECODE
--LEFT JOIN DS2FXRATE TGTFX
--	ON  TGTFX.EXRATEINTCODE = TGT.EXRATEINTCODE
--	AND TGTFX.EXRATEDATE = GBPFX.EXRATEDATE
WHERE F.EPS_NTM IS NOT NULL
	--AND F.ESTDATE = (SELECT MAX(ESTDATE) FROM FWD_12 WHERE ID = F.ID AND EPS_NTM IS NOT NULL AND ESTDATE <= GETDATE()) -- TO REPLICATE DFO 'STATIC REQUEST' FUNCTIONALITY

