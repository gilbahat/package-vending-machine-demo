

#include "VendManifest.h"

static inline uint64_t
ValidateVendEntry(
  uint8_t *Ctxt,
  void
  (*ErrorHandlerFn)(
    EVERPARSE_STRING x0,
    EVERPARSE_STRING x1,
    EVERPARSE_STRING x2,
    uint64_t x3,
    uint8_t *x4,
    uint8_t *x5,
    uint64_t x6
  ),
  uint8_t *Input,
  uint64_t InputLength,
  uint64_t StartPosition
)
{
  /* Checking that we have enough space for a UINT8, i.e., 1 byte */
  BOOLEAN hasBytes0 = 1ULL <= (InputLength - StartPosition);
  uint64_t positionAfterecosystem;
  if (hasBytes0)
  {
    positionAfterecosystem = StartPosition + 1ULL;
  }
  else
  {
    positionAfterecosystem =
      EverParseSetValidatorErrorPos(EVERPARSE_VALIDATOR_ERROR_NOT_ENOUGH_DATA,
        StartPosition);
  }
  uint64_t positionAfterVendEntry;
  if (EverParseIsError(positionAfterecosystem))
  {
    positionAfterVendEntry = positionAfterecosystem;
  }
  else
  {
    uint8_t ecosystem = Input[(uint32_t)StartPosition];
    BOOLEAN ecosystemConstraintIsOk = ecosystem <= VENDMANIFEST____ECOSYSTEM_NPM;
    uint64_t
    positionAfterecosystem1 =
      EverParseCheckConstraintOk(ecosystemConstraintIsOk,
        positionAfterecosystem);
    if (EverParseIsError(positionAfterecosystem1))
    {
      positionAfterVendEntry = positionAfterecosystem1;
    }
    else
    {
      /* Checking that we have enough space for a UINT8, i.e., 1 byte */
      BOOLEAN hasBytes1 = 1ULL <= (InputLength - positionAfterecosystem1);
      uint64_t positionAfternameLen;
      if (hasBytes1)
      {
        positionAfternameLen = positionAfterecosystem1 + 1ULL;
      }
      else
      {
        positionAfternameLen =
          EverParseSetValidatorErrorPos(EVERPARSE_VALIDATOR_ERROR_NOT_ENOUGH_DATA,
            positionAfterecosystem1);
      }
      uint64_t positionAfterVendEntry0;
      if (EverParseIsError(positionAfternameLen))
      {
        positionAfterVendEntry0 = positionAfternameLen;
      }
      else
      {
        uint8_t nameLen = Input[(uint32_t)positionAfterecosystem1];
        BOOLEAN nameLenConstraintIsOk = nameLen >= 1U && nameLen <= VENDMANIFEST____MAX_NAME_LEN;
        uint64_t
        positionAfternameLen1 =
          EverParseCheckConstraintOk(nameLenConstraintIsOk,
            positionAfternameLen);
        if (EverParseIsError(positionAfternameLen1))
        {
          positionAfterVendEntry0 = positionAfternameLen1;
        }
        else
        {
          /* Validating field name */
          BOOLEAN hasBytes = (uint64_t)(uint32_t)nameLen <= (InputLength - positionAfternameLen1);
          uint64_t res;
          if (hasBytes)
          {
            res = positionAfternameLen1 + (uint64_t)(uint32_t)nameLen;
          }
          else
          {
            res =
              EverParseSetValidatorErrorPos(EVERPARSE_VALIDATOR_ERROR_NOT_ENOUGH_DATA,
                positionAfternameLen1);
          }
          uint64_t positionAfterVendEntry1 = res;
          if (EverParseIsSuccess(positionAfterVendEntry1))
          {
            positionAfterVendEntry0 = positionAfterVendEntry1;
          }
          else
          {
            ErrorHandlerFn("_VendEntry",
              "name",
              EverParseErrorReasonOfResult(positionAfterVendEntry1),
              EverParseGetValidatorErrorKind(positionAfterVendEntry1),
              Ctxt,
              Input,
              positionAfternameLen1);
            positionAfterVendEntry0 = positionAfterVendEntry1;
          }
        }
      }
      if (EverParseIsSuccess(positionAfterVendEntry0))
      {
        positionAfterVendEntry = positionAfterVendEntry0;
      }
      else
      {
        ErrorHandlerFn("_VendEntry",
          "name_len",
          EverParseErrorReasonOfResult(positionAfterVendEntry0),
          EverParseGetValidatorErrorKind(positionAfterVendEntry0),
          Ctxt,
          Input,
          positionAfterecosystem1);
        positionAfterVendEntry = positionAfterVendEntry0;
      }
    }
  }
  if (EverParseIsSuccess(positionAfterVendEntry))
  {
    return positionAfterVendEntry;
  }
  ErrorHandlerFn("_VendEntry",
    "ecosystem",
    EverParseErrorReasonOfResult(positionAfterVendEntry),
    EverParseGetValidatorErrorKind(positionAfterVendEntry),
    Ctxt,
    Input,
    StartPosition);
  return positionAfterVendEntry;
}

uint64_t
VendManifestValidateVendManifest(
  uint8_t *Ctxt,
  void
  (*ErrorHandlerFn)(
    EVERPARSE_STRING x0,
    EVERPARSE_STRING x1,
    EVERPARSE_STRING x2,
    uint64_t x3,
    uint8_t *x4,
    uint8_t *x5,
    uint64_t x6
  ),
  uint8_t *Input,
  uint64_t InputLength,
  uint64_t StartPosition
)
{
  /* Checking that we have enough space for a UINT32BE, i.e., 4 bytes */
  BOOLEAN hasBytes0 = 4ULL <= (InputLength - StartPosition);
  uint64_t positionAftermagic;
  if (hasBytes0)
  {
    positionAftermagic = StartPosition + 4ULL;
  }
  else
  {
    positionAftermagic =
      EverParseSetValidatorErrorPos(EVERPARSE_VALIDATOR_ERROR_NOT_ENOUGH_DATA,
        StartPosition);
  }
  uint64_t positionAfterVendManifest;
  if (EverParseIsError(positionAftermagic))
  {
    positionAfterVendManifest = positionAftermagic;
  }
  else
  {
    uint32_t magic = Load32Be(Input + (uint32_t)StartPosition);
    BOOLEAN magicConstraintIsOk = magic == 1447904049U;
    uint64_t
    positionAftermagic1 = EverParseCheckConstraintOk(magicConstraintIsOk, positionAftermagic);
    if (EverParseIsError(positionAftermagic1))
    {
      positionAfterVendManifest = positionAftermagic1;
    }
    else
    {
      /* Checking that we have enough space for a UINT16BE, i.e., 2 bytes */
      BOOLEAN hasBytes1 = 2ULL <= (InputLength - positionAftermagic1);
      uint64_t positionAfterformatVersion;
      if (hasBytes1)
      {
        positionAfterformatVersion = positionAftermagic1 + 2ULL;
      }
      else
      {
        positionAfterformatVersion =
          EverParseSetValidatorErrorPos(EVERPARSE_VALIDATOR_ERROR_NOT_ENOUGH_DATA,
            positionAftermagic1);
      }
      uint64_t positionAfterVendManifest0;
      if (EverParseIsError(positionAfterformatVersion))
      {
        positionAfterVendManifest0 = positionAfterformatVersion;
      }
      else
      {
        uint16_t formatVersion = Load16Be(Input + (uint32_t)positionAftermagic1);
        BOOLEAN formatVersionConstraintIsOk = formatVersion == (uint16_t)1U;
        uint64_t
        positionAfterformatVersion1 =
          EverParseCheckConstraintOk(formatVersionConstraintIsOk,
            positionAfterformatVersion);
        if (EverParseIsError(positionAfterformatVersion1))
        {
          positionAfterVendManifest0 = positionAfterformatVersion1;
        }
        else
        {
          /* Checking that we have enough space for a UINT16BE, i.e., 2 bytes */
          BOOLEAN hasBytes2 = 2ULL <= (InputLength - positionAfterformatVersion1);
          uint64_t positionAfterreserved;
          if (hasBytes2)
          {
            positionAfterreserved = positionAfterformatVersion1 + 2ULL;
          }
          else
          {
            positionAfterreserved =
              EverParseSetValidatorErrorPos(EVERPARSE_VALIDATOR_ERROR_NOT_ENOUGH_DATA,
                positionAfterformatVersion1);
          }
          uint64_t positionAfterVendManifest1;
          if (EverParseIsError(positionAfterreserved))
          {
            positionAfterVendManifest1 = positionAfterreserved;
          }
          else
          {
            uint16_t reserved = Load16Be(Input + (uint32_t)positionAfterformatVersion1);
            BOOLEAN reservedConstraintIsOk = reserved == (uint16_t)0U;
            uint64_t
            positionAfterreserved1 =
              EverParseCheckConstraintOk(reservedConstraintIsOk,
                positionAfterreserved);
            if (EverParseIsError(positionAfterreserved1))
            {
              positionAfterVendManifest1 = positionAfterreserved1;
            }
            else
            {
              /* Checking that we have enough space for a UINT32BE, i.e., 4 bytes */
              BOOLEAN hasBytes = 4ULL <= (InputLength - positionAfterreserved1);
              uint64_t positionAfterentriesLen;
              if (hasBytes)
              {
                positionAfterentriesLen = positionAfterreserved1 + 4ULL;
              }
              else
              {
                positionAfterentriesLen =
                  EverParseSetValidatorErrorPos(EVERPARSE_VALIDATOR_ERROR_NOT_ENOUGH_DATA,
                    positionAfterreserved1);
              }
              uint64_t positionAfterVendManifest2;
              if (EverParseIsError(positionAfterentriesLen))
              {
                positionAfterVendManifest2 = positionAfterentriesLen;
              }
              else
              {
                uint32_t entriesLen = Load32Be(Input + (uint32_t)positionAfterreserved1);
                BOOLEAN entriesLenConstraintIsOk = entriesLen <= 1048576U;
                uint64_t
                positionAfterentriesLen1 =
                  EverParseCheckConstraintOk(entriesLenConstraintIsOk,
                    positionAfterentriesLen);
                if (EverParseIsError(positionAfterentriesLen1))
                {
                  positionAfterVendManifest2 = positionAfterentriesLen1;
                }
                else
                {
                  /* Validating field entries */
                  BOOLEAN
                  hasEnoughBytes = (uint64_t)entriesLen <= (InputLength - positionAfterentriesLen1);
                  uint64_t positionAfterVendManifest3;
                  if (!hasEnoughBytes)
                  {
                    positionAfterVendManifest3 =
                      EverParseSetValidatorErrorPos(EVERPARSE_VALIDATOR_ERROR_NOT_ENOUGH_DATA,
                        positionAfterentriesLen1);
                  }
                  else
                  {
                    uint8_t *truncatedInput = Input;
                    uint64_t truncatedInputLength = positionAfterentriesLen1 + (uint64_t)entriesLen;
                    uint64_t result = positionAfterentriesLen1;
                    while (TRUE)
                    {
                      uint64_t position = result;
                      BOOLEAN ite;
                      if (!(1ULL <= (truncatedInputLength - position)))
                      {
                        ite = TRUE;
                      }
                      else
                      {
                        uint64_t
                        positionAfterVendManifest4 =
                          ValidateVendEntry(Ctxt,
                            ErrorHandlerFn,
                            truncatedInput,
                            truncatedInputLength,
                            position);
                        uint64_t result1;
                        if (EverParseIsSuccess(positionAfterVendManifest4))
                        {
                          result1 = positionAfterVendManifest4;
                        }
                        else
                        {
                          ErrorHandlerFn("_VendManifest",
                            "entries.element",
                            EverParseErrorReasonOfResult(positionAfterVendManifest4),
                            EverParseGetValidatorErrorKind(positionAfterVendManifest4),
                            Ctxt,
                            truncatedInput,
                            position);
                          result1 = positionAfterVendManifest4;
                        }
                        result = result1;
                        ite = EverParseIsError(result1);
                      }
                      if (ite)
                      {
                        break;
                      }
                    }
                    uint64_t res = result;
                    positionAfterVendManifest3 = res;
                  }
                  if (EverParseIsSuccess(positionAfterVendManifest3))
                  {
                    positionAfterVendManifest2 = positionAfterVendManifest3;
                  }
                  else
                  {
                    ErrorHandlerFn("_VendManifest",
                      "entries",
                      EverParseErrorReasonOfResult(positionAfterVendManifest3),
                      EverParseGetValidatorErrorKind(positionAfterVendManifest3),
                      Ctxt,
                      Input,
                      positionAfterentriesLen1);
                    positionAfterVendManifest2 = positionAfterVendManifest3;
                  }
                }
              }
              if (EverParseIsSuccess(positionAfterVendManifest2))
              {
                positionAfterVendManifest1 = positionAfterVendManifest2;
              }
              else
              {
                ErrorHandlerFn("_VendManifest",
                  "entries_len",
                  EverParseErrorReasonOfResult(positionAfterVendManifest2),
                  EverParseGetValidatorErrorKind(positionAfterVendManifest2),
                  Ctxt,
                  Input,
                  positionAfterreserved1);
                positionAfterVendManifest1 = positionAfterVendManifest2;
              }
            }
          }
          if (EverParseIsSuccess(positionAfterVendManifest1))
          {
            positionAfterVendManifest0 = positionAfterVendManifest1;
          }
          else
          {
            ErrorHandlerFn("_VendManifest",
              "reserved",
              EverParseErrorReasonOfResult(positionAfterVendManifest1),
              EverParseGetValidatorErrorKind(positionAfterVendManifest1),
              Ctxt,
              Input,
              positionAfterformatVersion1);
            positionAfterVendManifest0 = positionAfterVendManifest1;
          }
        }
      }
      if (EverParseIsSuccess(positionAfterVendManifest0))
      {
        positionAfterVendManifest = positionAfterVendManifest0;
      }
      else
      {
        ErrorHandlerFn("_VendManifest",
          "format_version",
          EverParseErrorReasonOfResult(positionAfterVendManifest0),
          EverParseGetValidatorErrorKind(positionAfterVendManifest0),
          Ctxt,
          Input,
          positionAftermagic1);
        positionAfterVendManifest = positionAfterVendManifest0;
      }
    }
  }
  if (EverParseIsSuccess(positionAfterVendManifest))
  {
    return positionAfterVendManifest;
  }
  ErrorHandlerFn("_VendManifest",
    "magic",
    EverParseErrorReasonOfResult(positionAfterVendManifest),
    EverParseGetValidatorErrorKind(positionAfterVendManifest),
    Ctxt,
    Input,
    StartPosition);
  return positionAfterVendManifest;
}

