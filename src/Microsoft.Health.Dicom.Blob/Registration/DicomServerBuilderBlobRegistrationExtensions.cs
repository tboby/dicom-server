﻿// -------------------------------------------------------------------------------------------------
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License (MIT). See LICENSE in the repo root for license information.
// -------------------------------------------------------------------------------------------------

using EnsureThat;
using Microsoft.Extensions.Configuration;
using Microsoft.Health.Blob.Configs;
using Microsoft.Health.Dicom.Blob;
using Microsoft.Health.Dicom.Blob.Features.Health;
using Microsoft.Health.Dicom.Blob.Features.Storage;
using Microsoft.Health.Dicom.Core.Features.Common;
using Microsoft.Health.Dicom.Core.Registration;
using Microsoft.Health.Extensions.DependencyInjection;

namespace Microsoft.Extensions.DependencyInjection
{
    public static class DicomServerBuilderBlobRegistrationExtensions
    {
        private const string DicomServerBlobConfigurationSectionName = "DicomWeb:DicomStore";

        /// <summary>
        /// Adds the blob data store for the DICOM server.
        /// </summary>
        /// <param name="serverBuilder">The DICOM server builder instance.</param>
        /// <param name="configuration">The configuration for the server.</param>
        /// <returns>The server builder.</returns>
        public static IDicomServerBuilder AddBlobStorageDataStore(this IDicomServerBuilder serverBuilder, IConfiguration configuration)
        {
            EnsureArg.IsNotNull(serverBuilder, nameof(serverBuilder));
            EnsureArg.IsNotNull(configuration, nameof(configuration));

            return serverBuilder
                .AddBlobPersistence(configuration)
                .AddBlobHealthCheck();
        }

        private static IDicomServerBuilder AddBlobPersistence(this IDicomServerBuilder serverBuilder, IConfiguration configuration)
        {
            IServiceCollection services = serverBuilder.Services;

            IConfiguration blobConfig = configuration.GetSection(BlobServiceClientOptions.DefaultSectionName);
            services
                .AddBlobServiceClient(blobConfig)
                .AddBlobContainerInitialization(x => blobConfig
                    .GetSection(BlobInitializerOptions.DefaultSectionName)
                    .Bind(x))
                .ConfigureContainer(Constants.ContainerConfigurationName, x => configuration
                    .GetSection(DicomServerBlobConfigurationSectionName)
                    .Bind(x));

            services
                .AddOptions<BlobOperationOptions>()
                .Bind(blobConfig.GetSection(nameof(BlobServiceClientOptions.Operations)));

            services.Add<BlobFileStore>()
                .Scoped()
                .AsSelf()
                .AsImplementedInterfaces();

            // TODO: Ideally, the logger can be registered in the API layer since it's agnostic to the implementation.
            // However, the current implementation of the decorate method requires the concrete type to be already registered,
            // so we need to register here. Need to some more investigation to see how we might be able to do this.
            services.Decorate<IFileStore, LoggingFileStore>();

            return serverBuilder;
        }

        private static IDicomServerBuilder AddBlobHealthCheck(this IDicomServerBuilder serverBuilder)
        {
            serverBuilder.Services.AddHealthChecks().AddCheck<DicomBlobHealthCheck>(name: "DcmHealthCheck");
            return serverBuilder;
        }
    }
}
