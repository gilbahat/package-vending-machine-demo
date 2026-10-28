

#include "VendManifest.h"

static inline uint8_t
ValidateCoreVendEntry(
  uint8_t *Ctxt,
  void
  (*ErrorHandlerFn)(
    PRIMS_STRING x0,
    PRIMS_STRING x1,
    PRIMS_STRING x2,
    uint64_t x3,
    uint8_t *x4,
    uint8_t *x5,
    uint64_t x6
  ),
  uint8_t *SlBase,
  size_t SlLen,
  size_t *SlPos
)
{
  size_t p = *SlPos;
  uint64_t fieldStartVendEntry = (uint64_t)p;
  size_t pos = (size_t)0U;
  /* Checking that we have enough space for a UINT8, i.e., 1 byte */
  size_t p0 = pos;
  size_t p1 = *SlPos;
  size_t rem = SlLen - p1;
  BOOLEAN hasBytes = p0 <= rem && (size_t)1U <= (rem - p0);
  uint8_t resultAfterecosystem;
  if (hasBytes)
  {
    pos = p0 + (size_t)1U;
    resultAfterecosystem = EVERPARSEPULSEINTERNAL_VALIDATOR_SUCCESS;
  }
  else
  {
    resultAfterecosystem = EVERPARSEPULSEINTERNAL_VALIDATOR_ERROR_NOT_ENOUGH_DATA;
  }
  uint8_t resultAfterVendEntry;
  if (resultAfterecosystem == EVERPARSEPULSEINTERNAL_VALIDATOR_SUCCESS)
  {
    size_t p01 = *SlPos;
    size_t m = p01 + (size_t)1U;
    uint8_t *sub = SlBase + p01;
    *SlPos = m;
    uint8_t ecosystem = sub[0U];
    BOOLEAN ecosystemConstraintIsOk = ecosystem <= VENDMANIFEST____ECOSYSTEM_NPM;
    if (ecosystemConstraintIsOk)
    {
      size_t p2 = *SlPos;
      uint64_t fieldStartVendEntry1 = (uint64_t)p2;
      size_t pos1 = (size_t)0U;
      /* Checking that we have enough space for a UINT8, i.e., 1 byte */
      size_t p02 = pos1;
      size_t p3 = *SlPos;
      size_t rem1 = SlLen - p3;
      BOOLEAN hasBytes1 = p02 <= rem1 && (size_t)1U <= (rem1 - p02);
      uint8_t resultAfternameLen;
      if (hasBytes1)
      {
        pos1 = p02 + (size_t)1U;
        resultAfternameLen = EVERPARSEPULSEINTERNAL_VALIDATOR_SUCCESS;
      }
      else
      {
        resultAfternameLen = EVERPARSEPULSEINTERNAL_VALIDATOR_ERROR_NOT_ENOUGH_DATA;
      }
      uint8_t resultAfterVendEntry0;
      if (resultAfternameLen == EVERPARSEPULSEINTERNAL_VALIDATOR_SUCCESS)
      {
        size_t p03 = *SlPos;
        size_t m1 = p03 + (size_t)1U;
        uint8_t *sub1 = SlBase + p03;
        *SlPos = m1;
        uint8_t nameLen = sub1[0U];
        BOOLEAN nameLenConstraintIsOk = nameLen >= 1U && nameLen <= VENDMANIFEST____MAX_NAME_LEN;
        if (nameLenConstraintIsOk)
        {
          /* Validating field name */
          size_t p4 = *SlPos;
          uint64_t fieldStartVendEntry2 = (uint64_t)p4;
          size_t pos2 = (size_t)0U;
          size_t p04 = pos2;
          size_t p5 = *SlPos;
          size_t rem2 = SlLen - p5;
          BOOLEAN hasBytes2 = p04 <= rem2 && (size_t)(uint32_t)nameLen <= (rem2 - p04);
          uint8_t res;
          if (hasBytes2)
          {
            pos2 = p04 + (size_t)(uint32_t)nameLen;
            res = EVERPARSEPULSEINTERNAL_VALIDATOR_SUCCESS;
          }
          else
          {
            res = EVERPARSEPULSEINTERNAL_VALIDATOR_ERROR_NOT_ENOUGH_DATA;
          }
          uint8_t resultAfterVendEntry1;
          if (res == EVERPARSEPULSEINTERNAL_VALIDATOR_SUCCESS)
          {
            size_t consumed = pos2;
            size_t p6 = *SlPos;
            size_t p_ = p6 + consumed;
            *SlPos = p_;
            resultAfterVendEntry1 = EVERPARSEPULSEINTERNAL_VALIDATOR_SUCCESS;
          }
          else
          {
            resultAfterVendEntry1 = res;
          }
          if (resultAfterVendEntry1 == EVERPARSEPULSEINTERNAL_VALIDATOR_SUCCESS)
          {
            resultAfterVendEntry0 = resultAfterVendEntry1;
          }
          else
          {
            ErrorHandlerFn("_VendEntry",
              "name",
              EverParsePulseInternalErrorReasonOfResult(resultAfterVendEntry1),
              resultAfterVendEntry1 == 0U ||
                (resultAfterVendEntry1 >= 2U && resultAfterVendEntry1 <= 8U) ? (uint64_t)(uint32_t)resultAfterVendEntry1
                                                                             : 15ULL,
              Ctxt,
              SlBase,
              fieldStartVendEntry2);
            resultAfterVendEntry0 = resultAfterVendEntry1;
          }
        }
        else
        {
          resultAfterVendEntry0 = EVERPARSEPULSEINTERNAL_VALIDATOR_ERROR_CONSTRAINT_FAILED;
        }
      }
      else
      {
        resultAfterVendEntry0 = resultAfternameLen;
      }
      if (resultAfterVendEntry0 == EVERPARSEPULSEINTERNAL_VALIDATOR_SUCCESS)
      {
        resultAfterVendEntry = resultAfterVendEntry0;
      }
      else
      {
        ErrorHandlerFn("_VendEntry",
          "name_len",
          EverParsePulseInternalErrorReasonOfResult(resultAfterVendEntry0),
          resultAfterVendEntry0 == 0U ||
            (resultAfterVendEntry0 >= 2U && resultAfterVendEntry0 <= 8U) ? (uint64_t)(uint32_t)resultAfterVendEntry0
                                                                         : 15ULL,
          Ctxt,
          SlBase,
          fieldStartVendEntry1);
        resultAfterVendEntry = resultAfterVendEntry0;
      }
    }
    else
    {
      resultAfterVendEntry = EVERPARSEPULSEINTERNAL_VALIDATOR_ERROR_CONSTRAINT_FAILED;
    }
  }
  else
  {
    resultAfterVendEntry = resultAfterecosystem;
  }
  if (resultAfterVendEntry == EVERPARSEPULSEINTERNAL_VALIDATOR_SUCCESS)
  {
    return resultAfterVendEntry;
  }
  ErrorHandlerFn("_VendEntry",
    "ecosystem",
    EverParsePulseInternalErrorReasonOfResult(resultAfterVendEntry),
    resultAfterVendEntry == 0U || (resultAfterVendEntry >= 2U && resultAfterVendEntry <= 8U) ? (uint64_t)(uint32_t)resultAfterVendEntry
                                                                                             : 15ULL,
    Ctxt,
    SlBase,
    fieldStartVendEntry);
  return resultAfterVendEntry;
}

static uint8_t
ValidateCoreVendManifest(
  uint8_t *Ctxt,
  void
  (*ErrorHandlerFn)(
    PRIMS_STRING x0,
    PRIMS_STRING x1,
    PRIMS_STRING x2,
    uint64_t x3,
    uint8_t *x4,
    uint8_t *x5,
    uint64_t x6
  ),
  uint8_t *SlBase,
  size_t SlLen,
  size_t *SlPos
)
{
  size_t p = *SlPos;
  uint64_t fieldStartVendManifest = (uint64_t)p;
  size_t pos = (size_t)0U;
  /* Checking that we have enough space for a UINT32BE, i.e., 4 bytes */
  size_t p0 = pos;
  size_t p1 = *SlPos;
  size_t rem = SlLen - p1;
  BOOLEAN hasBytes = p0 <= rem && (size_t)4U <= (rem - p0);
  uint8_t resultAftermagic;
  if (hasBytes)
  {
    pos = p0 + (size_t)4U;
    resultAftermagic = EVERPARSEPULSEINTERNAL_VALIDATOR_SUCCESS;
  }
  else
  {
    resultAftermagic = EVERPARSEPULSEINTERNAL_VALIDATOR_ERROR_NOT_ENOUGH_DATA;
  }
  uint8_t resultAfterVendManifest;
  if (resultAftermagic == EVERPARSEPULSEINTERNAL_VALIDATOR_SUCCESS)
  {
    size_t p01 = *SlPos;
    size_t m = p01 + (size_t)4U;
    uint8_t *sub = SlBase + p01;
    *SlPos = m;
    uint8_t last = sub[3U];
    size_t pos_ = (size_t)3U - (size_t)1U;
    uint8_t last1 = sub[pos_];
    size_t pos_1 = pos_ - (size_t)1U;
    uint8_t last2 = sub[pos_1];
    uint8_t last3 = sub[0U];
    uint32_t n = (uint32_t)last3;
    uint32_t blast = (uint32_t)last2;
    uint32_t n1 = blast + n * 256U;
    uint32_t blast1 = (uint32_t)last1;
    uint32_t n2 = blast1 + n1 * 256U;
    uint32_t blast2 = (uint32_t)last;
    uint32_t magic = blast2 + n2 * 256U;
    BOOLEAN magicConstraintIsOk = magic == 1447904049U;
    if (magicConstraintIsOk)
    {
      size_t p2 = *SlPos;
      uint64_t fieldStartVendManifest1 = (uint64_t)p2;
      size_t pos1 = (size_t)0U;
      /* Checking that we have enough space for a UINT16BE, i.e., 2 bytes */
      size_t p02 = pos1;
      size_t p3 = *SlPos;
      size_t rem1 = SlLen - p3;
      BOOLEAN hasBytes1 = p02 <= rem1 && (size_t)2U <= (rem1 - p02);
      uint8_t resultAfterformatVersion;
      if (hasBytes1)
      {
        pos1 = p02 + (size_t)2U;
        resultAfterformatVersion = EVERPARSEPULSEINTERNAL_VALIDATOR_SUCCESS;
      }
      else
      {
        resultAfterformatVersion = EVERPARSEPULSEINTERNAL_VALIDATOR_ERROR_NOT_ENOUGH_DATA;
      }
      uint8_t resultAfterVendManifest0;
      if (resultAfterformatVersion == EVERPARSEPULSEINTERNAL_VALIDATOR_SUCCESS)
      {
        size_t p03 = *SlPos;
        size_t m1 = p03 + (size_t)2U;
        uint8_t *sub1 = SlBase + p03;
        *SlPos = m1;
        uint8_t last4 = sub1[1U];
        uint8_t last5 = sub1[0U];
        uint16_t n3 = (uint16_t)(uint32_t)last5;
        uint16_t blast3 = (uint16_t)(uint32_t)last4;
        uint16_t formatVersion = (uint32_t)blast3 + (uint32_t)n3 * 256U;
        BOOLEAN formatVersionConstraintIsOk = formatVersion == (uint16_t)1U;
        if (formatVersionConstraintIsOk)
        {
          size_t p4 = *SlPos;
          uint64_t fieldStartVendManifest2 = (uint64_t)p4;
          size_t pos2 = (size_t)0U;
          /* Checking that we have enough space for a UINT16BE, i.e., 2 bytes */
          size_t p04 = pos2;
          size_t p5 = *SlPos;
          size_t rem2 = SlLen - p5;
          BOOLEAN hasBytes2 = p04 <= rem2 && (size_t)2U <= (rem2 - p04);
          uint8_t resultAfterreserved;
          if (hasBytes2)
          {
            pos2 = p04 + (size_t)2U;
            resultAfterreserved = EVERPARSEPULSEINTERNAL_VALIDATOR_SUCCESS;
          }
          else
          {
            resultAfterreserved = EVERPARSEPULSEINTERNAL_VALIDATOR_ERROR_NOT_ENOUGH_DATA;
          }
          uint8_t resultAfterVendManifest1;
          if (resultAfterreserved == EVERPARSEPULSEINTERNAL_VALIDATOR_SUCCESS)
          {
            size_t p05 = *SlPos;
            size_t m2 = p05 + (size_t)2U;
            uint8_t *sub2 = SlBase + p05;
            *SlPos = m2;
            uint8_t last6 = sub2[1U];
            uint8_t last7 = sub2[0U];
            uint16_t n4 = (uint16_t)(uint32_t)last7;
            uint16_t blast4 = (uint16_t)(uint32_t)last6;
            uint16_t reserved = (uint32_t)blast4 + (uint32_t)n4 * 256U;
            BOOLEAN reservedConstraintIsOk = reserved == (uint16_t)0U;
            if (reservedConstraintIsOk)
            {
              size_t p6 = *SlPos;
              uint64_t fieldStartVendManifest3 = (uint64_t)p6;
              size_t pos3 = (size_t)0U;
              /* Checking that we have enough space for a UINT32BE, i.e., 4 bytes */
              size_t p06 = pos3;
              size_t p7 = *SlPos;
              size_t rem3 = SlLen - p7;
              BOOLEAN hasBytes3 = p06 <= rem3 && (size_t)4U <= (rem3 - p06);
              uint8_t resultAfterentriesLen;
              if (hasBytes3)
              {
                pos3 = p06 + (size_t)4U;
                resultAfterentriesLen = EVERPARSEPULSEINTERNAL_VALIDATOR_SUCCESS;
              }
              else
              {
                resultAfterentriesLen = EVERPARSEPULSEINTERNAL_VALIDATOR_ERROR_NOT_ENOUGH_DATA;
              }
              uint8_t resultAfterVendManifest2;
              if (resultAfterentriesLen == EVERPARSEPULSEINTERNAL_VALIDATOR_SUCCESS)
              {
                size_t p07 = *SlPos;
                size_t m3 = p07 + (size_t)4U;
                uint8_t *sub3 = SlBase + p07;
                *SlPos = m3;
                uint8_t last8 = sub3[3U];
                size_t pos_2 = (size_t)3U - (size_t)1U;
                uint8_t last9 = sub3[pos_2];
                size_t pos_3 = pos_2 - (size_t)1U;
                uint8_t last10 = sub3[pos_3];
                uint8_t last11 = sub3[0U];
                uint32_t n5 = (uint32_t)last11;
                uint32_t blast5 = (uint32_t)last10;
                uint32_t n6 = blast5 + n5 * 256U;
                uint32_t blast6 = (uint32_t)last9;
                uint32_t n7 = blast6 + n6 * 256U;
                uint32_t blast7 = (uint32_t)last8;
                uint32_t entriesLen = blast7 + n7 * 256U;
                BOOLEAN entriesLenConstraintIsOk = entriesLen <= 1048576U;
                if (entriesLenConstraintIsOk)
                {
                  /* Validating field entries */
                  size_t p8 = *SlPos;
                  uint64_t fieldStartVendManifest4 = (uint64_t)p8;
                  size_t nSz = (size_t)entriesLen;
                  size_t p9 = *SlPos;
                  size_t avail = SlLen - p9;
                  BOOLEAN hasBytes4 = nSz <= avail;
                  uint8_t resultAfterVendManifest3;
                  if (!hasBytes4)
                  {
                    resultAfterVendManifest3 =
                      EVERPARSEPULSEINTERNAL_VALIDATOR_ERROR_NOT_ENOUGH_DATA;
                  }
                  else
                  {
                    size_t p10 = *SlPos;
                    size_t tr = p10 + nSz;
                    uint8_t res = EVERPARSEPULSEINTERNAL_VALIDATOR_SUCCESS;
                    BOOLEAN stop = FALSE;
                    BOOLEAN anf0 = stop;
                    BOOLEAN cond = !anf0;
                    while (cond)
                    {
                      size_t p11 = *SlPos;
                      size_t avail1 = tr - p11;
                      BOOLEAN hasMore = (size_t)1U <= avail1;
                      if (!hasMore)
                      {
                        stop = TRUE;
                      }
                      else
                      {
                        size_t p12 = *SlPos;
                        uint64_t fieldStartVendManifest5 = (uint64_t)p12;
                        uint8_t
                        resultAfterVendManifest4 =
                          ValidateCoreVendEntry(Ctxt,
                            ErrorHandlerFn,
                            SlBase,
                            tr,
                            SlPos);
                        uint8_t r;
                        if (resultAfterVendManifest4 == EVERPARSEPULSEINTERNAL_VALIDATOR_SUCCESS)
                        {
                          r = resultAfterVendManifest4;
                        }
                        else
                        {
                          ErrorHandlerFn("_VendManifest",
                            "entries.element",
                            EverParsePulseInternalErrorReasonOfResult(resultAfterVendManifest4),
                            resultAfterVendManifest4 == 0U ||
                              (resultAfterVendManifest4 >= 2U && resultAfterVendManifest4 <= 8U) ? (uint64_t)(uint32_t)resultAfterVendManifest4
                                                                                                 : 15ULL,
                            Ctxt,
                            SlBase,
                            fieldStartVendManifest5);
                          r = resultAfterVendManifest4;
                        }
                        if (!(r == EVERPARSEPULSEINTERNAL_VALIDATOR_SUCCESS))
                        {
                          res = r;
                          stop = TRUE;
                        }
                      }
                      BOOLEAN anf00 = stop;
                      cond = !anf00;
                    }
                    uint8_t fres = res;
                    resultAfterVendManifest3 =
                      fres == EVERPARSEPULSEINTERNAL_VALIDATOR_SUCCESS ? fres
                                                                       : fres;
                  }
                  if (resultAfterVendManifest3 == EVERPARSEPULSEINTERNAL_VALIDATOR_SUCCESS)
                  {
                    resultAfterVendManifest2 = resultAfterVendManifest3;
                  }
                  else
                  {
                    ErrorHandlerFn("_VendManifest",
                      "entries",
                      EverParsePulseInternalErrorReasonOfResult(resultAfterVendManifest3),
                      resultAfterVendManifest3 == 0U ||
                        (resultAfterVendManifest3 >= 2U && resultAfterVendManifest3 <= 8U) ? (uint64_t)(uint32_t)resultAfterVendManifest3
                                                                                           : 15ULL,
                      Ctxt,
                      SlBase,
                      fieldStartVendManifest4);
                    resultAfterVendManifest2 = resultAfterVendManifest3;
                  }
                }
                else
                {
                  resultAfterVendManifest2 =
                    EVERPARSEPULSEINTERNAL_VALIDATOR_ERROR_CONSTRAINT_FAILED;
                }
              }
              else
              {
                resultAfterVendManifest2 = resultAfterentriesLen;
              }
              if (resultAfterVendManifest2 == EVERPARSEPULSEINTERNAL_VALIDATOR_SUCCESS)
              {
                resultAfterVendManifest1 = resultAfterVendManifest2;
              }
              else
              {
                ErrorHandlerFn("_VendManifest",
                  "entries_len",
                  EverParsePulseInternalErrorReasonOfResult(resultAfterVendManifest2),
                  resultAfterVendManifest2 == 0U ||
                    (resultAfterVendManifest2 >= 2U && resultAfterVendManifest2 <= 8U) ? (uint64_t)(uint32_t)resultAfterVendManifest2
                                                                                       : 15ULL,
                  Ctxt,
                  SlBase,
                  fieldStartVendManifest3);
                resultAfterVendManifest1 = resultAfterVendManifest2;
              }
            }
            else
            {
              resultAfterVendManifest1 = EVERPARSEPULSEINTERNAL_VALIDATOR_ERROR_CONSTRAINT_FAILED;
            }
          }
          else
          {
            resultAfterVendManifest1 = resultAfterreserved;
          }
          if (resultAfterVendManifest1 == EVERPARSEPULSEINTERNAL_VALIDATOR_SUCCESS)
          {
            resultAfterVendManifest0 = resultAfterVendManifest1;
          }
          else
          {
            ErrorHandlerFn("_VendManifest",
              "reserved",
              EverParsePulseInternalErrorReasonOfResult(resultAfterVendManifest1),
              resultAfterVendManifest1 == 0U ||
                (resultAfterVendManifest1 >= 2U && resultAfterVendManifest1 <= 8U) ? (uint64_t)(uint32_t)resultAfterVendManifest1
                                                                                   : 15ULL,
              Ctxt,
              SlBase,
              fieldStartVendManifest2);
            resultAfterVendManifest0 = resultAfterVendManifest1;
          }
        }
        else
        {
          resultAfterVendManifest0 = EVERPARSEPULSEINTERNAL_VALIDATOR_ERROR_CONSTRAINT_FAILED;
        }
      }
      else
      {
        resultAfterVendManifest0 = resultAfterformatVersion;
      }
      if (resultAfterVendManifest0 == EVERPARSEPULSEINTERNAL_VALIDATOR_SUCCESS)
      {
        resultAfterVendManifest = resultAfterVendManifest0;
      }
      else
      {
        ErrorHandlerFn("_VendManifest",
          "format_version",
          EverParsePulseInternalErrorReasonOfResult(resultAfterVendManifest0),
          resultAfterVendManifest0 == 0U ||
            (resultAfterVendManifest0 >= 2U && resultAfterVendManifest0 <= 8U) ? (uint64_t)(uint32_t)resultAfterVendManifest0
                                                                               : 15ULL,
          Ctxt,
          SlBase,
          fieldStartVendManifest1);
        resultAfterVendManifest = resultAfterVendManifest0;
      }
    }
    else
    {
      resultAfterVendManifest = EVERPARSEPULSEINTERNAL_VALIDATOR_ERROR_CONSTRAINT_FAILED;
    }
  }
  else
  {
    resultAfterVendManifest = resultAftermagic;
  }
  if (resultAfterVendManifest == EVERPARSEPULSEINTERNAL_VALIDATOR_SUCCESS)
  {
    return resultAfterVendManifest;
  }
  ErrorHandlerFn("_VendManifest",
    "magic",
    EverParsePulseInternalErrorReasonOfResult(resultAfterVendManifest),
    resultAfterVendManifest == 0U ||
      (resultAfterVendManifest >= 2U && resultAfterVendManifest <= 8U) ? (uint64_t)(uint32_t)resultAfterVendManifest
                                                                       : 15ULL,
    Ctxt,
    SlBase,
    fieldStartVendManifest);
  return resultAfterVendManifest;
}

uint64_t
VendManifestValidateVendManifest(
  uint8_t *Ctxt,
  void
  (*Handler)(
    PRIMS_STRING x0,
    PRIMS_STRING x1,
    PRIMS_STRING x2,
    uint64_t x3,
    uint8_t *x4,
    uint8_t *x5,
    uint64_t x6
  ),
  uint8_t *Input,
  uint64_t Length,
  uint64_t Start
)
{
  size_t len = (size_t)Length;
  size_t initial = (size_t)Start;
  size_t cursor = initial;
  uint8_t status = ValidateCoreVendManifest(Ctxt, Handler, Input, len, &cursor);
  size_t final = cursor;
  uint64_t position = (uint64_t)final;
  return
    (status == 0U || (status >= 2U && status <= 8U) ? (uint64_t)(uint32_t)status : 15ULL) *
      1152921504606846976ULL
    + position;
}

