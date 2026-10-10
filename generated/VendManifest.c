

#include "VendManifest.h"

#include "EverParse.h"

static inline uint64_t
ValidateVendEntry(
  uint8_t *Ctxt,
  EVERPARSE_ERROR_HANDLER ErrorHandlerFn,
  uint8_t *Input,
  uint64_t InputLength,
  uint64_t StartPosition
)
{
  /* Checking that we have enough space for a UINT8, i.e., 1 byte */
  BOOLEAN hasBytesForEcosystem = (InputLength - StartPosition) >= 1ULL;
  uint64_t positionAfterEcosystem;
  if (hasBytesForEcosystem)
  {
    positionAfterEcosystem = StartPosition + 1ULL;
  }
  else
  {
    positionAfterEcosystem =
      EverParseSetValidatorErrorPos(EVERPARSE_VALIDATOR_ERROR_NOT_ENOUGH_DATA,
        StartPosition);
  }
  uint64_t positionAfterEcosystemOrError;
  if (EverParseIsError(positionAfterEcosystem))
  {
    positionAfterEcosystemOrError = positionAfterEcosystem;
  }
  else
  {
    uint8_t ecosystem = Input[(uint32_t)StartPosition];
    BOOLEAN ecosystemConstraintIsOk = ecosystem <= VENDMANIFEST____ECOSYSTEM_NPM;
    uint64_t
    positionAfterCheckedEcosystem =
      EverParseCheckConstraintOk(ecosystemConstraintIsOk,
        positionAfterEcosystem);
    if (EverParseIsError(positionAfterCheckedEcosystem))
    {
      positionAfterEcosystemOrError = positionAfterCheckedEcosystem;
    }
    else
    {
      /* Checking that we have enough space for a UINT8, i.e., 1 byte */
      BOOLEAN hasBytesForNameLen = (InputLength - positionAfterCheckedEcosystem) >= 1ULL;
      uint64_t positionAfterNameLen;
      if (hasBytesForNameLen)
      {
        positionAfterNameLen = positionAfterCheckedEcosystem + 1ULL;
      }
      else
      {
        positionAfterNameLen =
          EverParseSetValidatorErrorPos(EVERPARSE_VALIDATOR_ERROR_NOT_ENOUGH_DATA,
            positionAfterCheckedEcosystem);
      }
      uint64_t positionAfterNameLenOrError;
      if (EverParseIsError(positionAfterNameLen))
      {
        positionAfterNameLenOrError = positionAfterNameLen;
      }
      else
      {
        uint8_t nameLen = Input[(uint32_t)positionAfterCheckedEcosystem];
        BOOLEAN nameLenConstraintIsOk = nameLen >= 1U && nameLen <= VENDMANIFEST____MAX_NAME_LEN;
        uint64_t
        positionAfterCheckedNameLen =
          EverParseCheckConstraintOk(nameLenConstraintIsOk,
            positionAfterNameLen);
        if (EverParseIsError(positionAfterCheckedNameLen))
        {
          positionAfterNameLenOrError = positionAfterCheckedNameLen;
        }
        else
        {
          /* Validating field name */
          BOOLEAN
          hasBytesForName =
            (InputLength - positionAfterCheckedNameLen) >= (uint64_t)(uint32_t)nameLen;
          uint64_t resForName;
          if (hasBytesForName)
          {
            resForName = positionAfterCheckedNameLen + (uint64_t)(uint32_t)nameLen;
          }
          else
          {
            resForName =
              EverParseSetValidatorErrorPos(EVERPARSE_VALIDATOR_ERROR_NOT_ENOUGH_DATA,
                positionAfterCheckedNameLen);
          }
          uint64_t positionAfterNameOrError = resForName;
          if (EverParseIsSuccess(positionAfterNameOrError))
          {
            positionAfterNameLenOrError = positionAfterNameOrError;
          }
          else
          {
            ErrorHandlerFn("_VendEntry",
              "name",
              EverParseErrorReasonOfResult(positionAfterNameOrError),
              EverParseGetValidatorErrorKind(positionAfterNameOrError),
              Ctxt,
              Input,
              positionAfterCheckedNameLen);
            positionAfterNameLenOrError = positionAfterNameOrError;
          }
        }
      }
      if (EverParseIsSuccess(positionAfterNameLenOrError))
      {
        positionAfterEcosystemOrError = positionAfterNameLenOrError;
      }
      else
      {
        ErrorHandlerFn("_VendEntry",
          "name_len",
          EverParseErrorReasonOfResult(positionAfterNameLenOrError),
          EverParseGetValidatorErrorKind(positionAfterNameLenOrError),
          Ctxt,
          Input,
          positionAfterCheckedEcosystem);
        positionAfterEcosystemOrError = positionAfterNameLenOrError;
      }
    }
  }
  if (EverParseIsSuccess(positionAfterEcosystemOrError))
  {
    return positionAfterEcosystemOrError;
  }
  ErrorHandlerFn("_VendEntry",
    "ecosystem",
    EverParseErrorReasonOfResult(positionAfterEcosystemOrError),
    EverParseGetValidatorErrorKind(positionAfterEcosystemOrError),
    Ctxt,
    Input,
    StartPosition);
  return positionAfterEcosystemOrError;
}

uint64_t
VendManifestValidateVendManifest(
  uint8_t *Ctxt,
  EVERPARSE_ERROR_HANDLER ErrorHandlerFn,
  uint8_t *Input,
  uint64_t InputLength,
  uint64_t StartPosition
)
{
  /* Checking that we have enough space for a UINT32BE, i.e., 4 bytes */
  BOOLEAN hasBytesForMagic = (InputLength - StartPosition) >= 4ULL;
  uint64_t positionAfterMagic;
  if (hasBytesForMagic)
  {
    positionAfterMagic = StartPosition + 4ULL;
  }
  else
  {
    positionAfterMagic =
      EverParseSetValidatorErrorPos(EVERPARSE_VALIDATOR_ERROR_NOT_ENOUGH_DATA,
        StartPosition);
  }
  uint64_t positionAfterMagicOrError;
  if (EverParseIsError(positionAfterMagic))
  {
    positionAfterMagicOrError = positionAfterMagic;
  }
  else
  {
    uint32_t magic = Load32Be(Input + (uint32_t)StartPosition);
    BOOLEAN magicConstraintIsOk = magic == 1447904049U;
    uint64_t
    positionAfterCheckedMagic = EverParseCheckConstraintOk(magicConstraintIsOk, positionAfterMagic);
    if (EverParseIsError(positionAfterCheckedMagic))
    {
      positionAfterMagicOrError = positionAfterCheckedMagic;
    }
    else
    {
      /* Checking that we have enough space for a UINT16BE, i.e., 2 bytes */
      BOOLEAN hasBytesForFormatVersion = (InputLength - positionAfterCheckedMagic) >= 2ULL;
      uint64_t positionAfterFormatVersion;
      if (hasBytesForFormatVersion)
      {
        positionAfterFormatVersion = positionAfterCheckedMagic + 2ULL;
      }
      else
      {
        positionAfterFormatVersion =
          EverParseSetValidatorErrorPos(EVERPARSE_VALIDATOR_ERROR_NOT_ENOUGH_DATA,
            positionAfterCheckedMagic);
      }
      uint64_t positionAfterFormatVersionOrError;
      if (EverParseIsError(positionAfterFormatVersion))
      {
        positionAfterFormatVersionOrError = positionAfterFormatVersion;
      }
      else
      {
        uint16_t formatVersion = Load16Be(Input + (uint32_t)positionAfterCheckedMagic);
        BOOLEAN formatVersionConstraintIsOk = formatVersion == (uint16_t)1U;
        uint64_t
        positionAfterCheckedFormatVersion =
          EverParseCheckConstraintOk(formatVersionConstraintIsOk,
            positionAfterFormatVersion);
        if (EverParseIsError(positionAfterCheckedFormatVersion))
        {
          positionAfterFormatVersionOrError = positionAfterCheckedFormatVersion;
        }
        else
        {
          /* Checking that we have enough space for a UINT16BE, i.e., 2 bytes */
          BOOLEAN hasBytesForReserved = (InputLength - positionAfterCheckedFormatVersion) >= 2ULL;
          uint64_t positionAfterReserved;
          if (hasBytesForReserved)
          {
            positionAfterReserved = positionAfterCheckedFormatVersion + 2ULL;
          }
          else
          {
            positionAfterReserved =
              EverParseSetValidatorErrorPos(EVERPARSE_VALIDATOR_ERROR_NOT_ENOUGH_DATA,
                positionAfterCheckedFormatVersion);
          }
          uint64_t positionAfterReservedOrError;
          if (EverParseIsError(positionAfterReserved))
          {
            positionAfterReservedOrError = positionAfterReserved;
          }
          else
          {
            uint16_t reserved = Load16Be(Input + (uint32_t)positionAfterCheckedFormatVersion);
            BOOLEAN reservedConstraintIsOk = reserved == (uint16_t)0U;
            uint64_t
            positionAfterCheckedReserved =
              EverParseCheckConstraintOk(reservedConstraintIsOk,
                positionAfterReserved);
            if (EverParseIsError(positionAfterCheckedReserved))
            {
              positionAfterReservedOrError = positionAfterCheckedReserved;
            }
            else
            {
              /* Checking that we have enough space for a UINT32BE, i.e., 4 bytes */
              BOOLEAN hasBytesForEntriesLen = (InputLength - positionAfterCheckedReserved) >= 4ULL;
              uint64_t positionAfterEntriesLen;
              if (hasBytesForEntriesLen)
              {
                positionAfterEntriesLen = positionAfterCheckedReserved + 4ULL;
              }
              else
              {
                positionAfterEntriesLen =
                  EverParseSetValidatorErrorPos(EVERPARSE_VALIDATOR_ERROR_NOT_ENOUGH_DATA,
                    positionAfterCheckedReserved);
              }
              uint64_t positionAfterEntriesLenOrError;
              if (EverParseIsError(positionAfterEntriesLen))
              {
                positionAfterEntriesLenOrError = positionAfterEntriesLen;
              }
              else
              {
                uint32_t entriesLen = Load32Be(Input + (uint32_t)positionAfterCheckedReserved);
                BOOLEAN entriesLenConstraintIsOk = entriesLen <= 1048576U;
                uint64_t
                positionAfterCheckedEntriesLen =
                  EverParseCheckConstraintOk(entriesLenConstraintIsOk,
                    positionAfterEntriesLen);
                if (EverParseIsError(positionAfterCheckedEntriesLen))
                {
                  positionAfterEntriesLenOrError = positionAfterCheckedEntriesLen;
                }
                else
                {
                  /* Validating field entries */
                  BOOLEAN
                  hasEnoughBytes =
                    (InputLength - positionAfterCheckedEntriesLen) >= (uint64_t)entriesLen;
                  uint64_t positionAfterEntriesOrError;
                  if (!hasEnoughBytes)
                  {
                    positionAfterEntriesOrError =
                      EverParseSetValidatorErrorPos(EVERPARSE_VALIDATOR_ERROR_NOT_ENOUGH_DATA,
                        positionAfterCheckedEntriesLen);
                  }
                  else
                  {
                    uint8_t *truncatedInput = Input;
                    uint64_t
                    truncatedInputLength = positionAfterCheckedEntriesLen + (uint64_t)entriesLen;
                    uint64_t listResultForEntries = positionAfterCheckedEntriesLen;
                    while (TRUE)
                    {
                      uint64_t position = listResultForEntries;
                      BOOLEAN ite;
                      if (!((truncatedInputLength - position) >= 1ULL))
                      {
                        ite = TRUE;
                      }
                      else
                      {
                        uint64_t
                        positionAfterEntries_elementOrError =
                          ValidateVendEntry(Ctxt,
                            ErrorHandlerFn,
                            truncatedInput,
                            truncatedInputLength,
                            position);
                        uint64_t resultForEntries;
                        if (EverParseIsSuccess(positionAfterEntries_elementOrError))
                        {
                          resultForEntries = positionAfterEntries_elementOrError;
                        }
                        else
                        {
                          ErrorHandlerFn("_VendManifest",
                            "entries.element",
                            EverParseErrorReasonOfResult(positionAfterEntries_elementOrError),
                            EverParseGetValidatorErrorKind(positionAfterEntries_elementOrError),
                            Ctxt,
                            truncatedInput,
                            position);
                          resultForEntries = positionAfterEntries_elementOrError;
                        }
                        listResultForEntries = resultForEntries;
                        ite = EverParseIsError(resultForEntries);
                      }
                      if (ite)
                      {
                        break;
                      }
                    }
                    uint64_t resForEntries = listResultForEntries;
                    positionAfterEntriesOrError = resForEntries;
                  }
                  if (EverParseIsSuccess(positionAfterEntriesOrError))
                  {
                    positionAfterEntriesLenOrError = positionAfterEntriesOrError;
                  }
                  else
                  {
                    ErrorHandlerFn("_VendManifest",
                      "entries",
                      EverParseErrorReasonOfResult(positionAfterEntriesOrError),
                      EverParseGetValidatorErrorKind(positionAfterEntriesOrError),
                      Ctxt,
                      Input,
                      positionAfterCheckedEntriesLen);
                    positionAfterEntriesLenOrError = positionAfterEntriesOrError;
                  }
                }
              }
              if (EverParseIsSuccess(positionAfterEntriesLenOrError))
              {
                positionAfterReservedOrError = positionAfterEntriesLenOrError;
              }
              else
              {
                ErrorHandlerFn("_VendManifest",
                  "entries_len",
                  EverParseErrorReasonOfResult(positionAfterEntriesLenOrError),
                  EverParseGetValidatorErrorKind(positionAfterEntriesLenOrError),
                  Ctxt,
                  Input,
                  positionAfterCheckedReserved);
                positionAfterReservedOrError = positionAfterEntriesLenOrError;
              }
            }
          }
          if (EverParseIsSuccess(positionAfterReservedOrError))
          {
            positionAfterFormatVersionOrError = positionAfterReservedOrError;
          }
          else
          {
            ErrorHandlerFn("_VendManifest",
              "reserved",
              EverParseErrorReasonOfResult(positionAfterReservedOrError),
              EverParseGetValidatorErrorKind(positionAfterReservedOrError),
              Ctxt,
              Input,
              positionAfterCheckedFormatVersion);
            positionAfterFormatVersionOrError = positionAfterReservedOrError;
          }
        }
      }
      if (EverParseIsSuccess(positionAfterFormatVersionOrError))
      {
        positionAfterMagicOrError = positionAfterFormatVersionOrError;
      }
      else
      {
        ErrorHandlerFn("_VendManifest",
          "format_version",
          EverParseErrorReasonOfResult(positionAfterFormatVersionOrError),
          EverParseGetValidatorErrorKind(positionAfterFormatVersionOrError),
          Ctxt,
          Input,
          positionAfterCheckedMagic);
        positionAfterMagicOrError = positionAfterFormatVersionOrError;
      }
    }
  }
  if (EverParseIsSuccess(positionAfterMagicOrError))
  {
    return positionAfterMagicOrError;
  }
  ErrorHandlerFn("_VendManifest",
    "magic",
    EverParseErrorReasonOfResult(positionAfterMagicOrError),
    EverParseGetValidatorErrorKind(positionAfterMagicOrError),
    Ctxt,
    Input,
    StartPosition);
  return positionAfterMagicOrError;
}

