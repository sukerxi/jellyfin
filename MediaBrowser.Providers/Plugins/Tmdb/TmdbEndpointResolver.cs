using System;
using System.Diagnostics.CodeAnalysis;

namespace MediaBrowser.Providers.Plugins.Tmdb
{
    /// <summary>
    /// Resolves the TMDb API and image endpoints, applying the optional reverse-proxy
    /// overrides configured in <see cref="PluginConfiguration"/>.
    /// </summary>
    /// <remarks>
    /// Empty or malformed overrides are ignored, so callers transparently fall back to
    /// the official TMDb endpoints instead of producing unusable URLs.
    /// </remarks>
    internal static class TmdbEndpointResolver
    {
        /// <summary>
        /// Gets the custom API endpoint in the shape expected by <see cref="TMDbLib.Client.TMDbClient"/>:
        /// the host and an optional reverse-proxy path, without scheme or trailing slash,
        /// together with whether HTTPS should be used.
        /// </summary>
        /// <param name="host">The host (and optional path) of the reverse proxy.</param>
        /// <param name="useSsl">Whether the client should use HTTPS.</param>
        /// <returns><c>true</c> if a valid override is configured; otherwise <c>false</c>.</returns>
        public static bool TryGetApiEndpoint([NotNullWhen(true)] out string? host, out bool useSsl)
        {
            if (!TryParse(Plugin.Instance.Configuration.TmdbApiUrl, out var uri))
            {
                host = null;
                useSsl = true;
                return false;
            }

            // TMDbClient strips the scheme itself and rebuilds the URL as
            // "{scheme}://{host}/3/", so pass through only the authority and the
            // optional proxy path without a trailing slash.
            host = uri.Authority + uri.AbsolutePath.TrimEnd('/');
            useSsl = string.Equals(uri.Scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase);
            return true;
        }

        /// <summary>
        /// Builds an image URL through the configured image proxy, mirroring the
        /// <c>/t/p/{size}{path}</c> layout used by the official image endpoint.
        /// </summary>
        /// <param name="size">The image size, e.g. <c>w500</c> or <c>original</c>.</param>
        /// <param name="path">The image path returned by TMDb.</param>
        /// <param name="url">The proxied absolute URL.</param>
        /// <returns><c>true</c> if a valid override is configured; otherwise <c>false</c>.</returns>
        public static bool TryGetImageUrl(string size, string path, [NotNullWhen(true)] out string? url)
        {
            if (!TryParse(Plugin.Instance.Configuration.TmdbImageUrl, out var uri))
            {
                url = null;
                return false;
            }

            // TMDb paths normally start with '/'; normalise defensively to avoid double
            // or missing separators in the generated URL.
            if (!path.StartsWith('/'))
            {
                path = "/" + path;
            }

            url = uri.ToString().TrimEnd('/') + "/t/p/" + size + path;
            return true;
        }

        /// <summary>
        /// Validates and normalises a configured endpoint. A value without a scheme is
        /// assumed to be HTTPS, matching the official TMDb endpoints.
        /// </summary>
        private static bool TryParse(string? configured, [NotNullWhen(true)] out Uri? uri)
        {
            uri = null;

            if (string.IsNullOrWhiteSpace(configured))
            {
                return false;
            }

            var value = configured.Trim();
            if (!value.Contains("://", StringComparison.Ordinal))
            {
                value = Uri.UriSchemeHttps + Uri.SchemeDelimiter + value;
            }

            return Uri.TryCreate(value, UriKind.Absolute, out uri)
                && (string.Equals(uri.Scheme, Uri.UriSchemeHttp, StringComparison.OrdinalIgnoreCase)
                    || string.Equals(uri.Scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase))
                && !string.IsNullOrEmpty(uri.Authority);
        }
    }
}
