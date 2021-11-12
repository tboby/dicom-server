// -------------------------------------------------------------------------------------------------
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License (MIT). See LICENSE in the repo root for license information.
// -------------------------------------------------------------------------------------------------

using Dicom;
using EnsureThat;
using Microsoft.Health.Dicom.Core.Exceptions;
using Microsoft.Health.Dicom.Core.Extensions;
using Microsoft.Health.Dicom.Core.Features.ExtendedQueryTag;

namespace Microsoft.Health.Dicom.Core.Features.Validation
{
    internal static class ImplicitValueRepresentationValidator
    {
        public static void Validate(QueryTag queryTag)
        {
            EnsureArg.IsNotNull(queryTag, nameof(queryTag));

            Validate(queryTag.VR, queryTag.Tag);
        }

        public static void Validate(DicomItem dicomItem)
        {
            EnsureArg.IsNotNull(dicomItem, nameof(dicomItem));

            Validate(dicomItem.ValueRepresentation, dicomItem.Tag);
        }

        private static void Validate(DicomVR vr, DicomTag tag)
        {
            // From Dicom.Core source:
            // When VR is implicit, Tag.VR is initialized with DicomVR.NONE
            // But in the Explicit-Implicit case VR is initialized with an Empty DicomVR().
            // Hence checking for the null "Type" is equivalent to checking for "Implicit VR" in this scenario.
            if (vr == null || vr == DicomVR.NONE || vr.ValueType == null)
            {
                throw ElementValidationExceptionFactory.CreateImplicitVRException(tag.GetFriendlyName(), vr);
            }
        }
    }
}
