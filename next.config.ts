import type { NextConfig } from 'next'

/**
 * Static export: the whole site is plain files, so it can be hosted on
 * GitHub Pages (or Vercel, Netlify, anywhere). On GitHub Pages a project
 * site lives under /<repo>, so the deploy workflow sets NEXT_PUBLIC_BASE_PATH.
 */
const basePath = process.env.NEXT_PUBLIC_BASE_PATH || ''

const nextConfig: NextConfig = {
  output: 'export',
  basePath,
  trailingSlash: true,
  images: { unoptimized: true },
  // Strict mode double-mounts effects in development, which would register
  // the host with the broker twice and make it wait to reclaim its own code.
  reactStrictMode: false,
}

export default nextConfig
