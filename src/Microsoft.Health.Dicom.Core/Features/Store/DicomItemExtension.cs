// -------------------------------------------------------------------------------------------------
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License (MIT). See LICENSE in the repo root for license information.
// -------------------------------------------------------------------------------------------------

using Dicom;
using EnsureThat;
using Microsoft.Health.Dicom.Core.Features.Validation;

namespace Microsoft.Health.Dicom.Core.Features.Store
{
    public static class DicomItemExtension
    {
        public static void ValidateDicomItem(this DicomItem dicomItem)
        {
            EnsureArg.IsNotNull(dicomItem, nameof(dicomItem));
            try
            {
                dicomItem.Validate();

                ImplicitValueRepresentationValidator.Validate(dicomItem);
            }
            catch (DicomValidationException ex)
            {
                throw new DatasetValidationException(
                    FailureReasonCodes.ValidationFailure,
                    ex.Message,
                    ex);
            }
        }
    }
}
