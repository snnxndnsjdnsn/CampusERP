import nextConfig from 'eslint-config-next';

/**
 * ESLint flat config.
 *
 * `eslint-config-next` v16 ships its rules as a flat config array already, so
 * it is used directly. The core-web-vitals rules catch the mistakes that
 * actually bite in this app: missing `alt` text, unoptimised images, and
 * hooks used conditionally.
 */
export default [
  {
    ignores: [
      '.next/**',
      'node_modules/**',
      'out/**',
      'build/**',
      'next-env.d.ts',
      'tools/**',
      'supabase/**',
      'coverage/**',
      'playwright-report/**',
      'test-results/**',
    ],
  },
  ...nextConfig,
  {
    rules: {
      // The database is the authorisation boundary, so a page that fetches data
      // is expected to be an async server component. These rules are relaxed
      // because the codebase deliberately uses precise generics in a few
      // database-result shapes.
      '@typescript-eslint/no-explicit-any': 'warn',
      '@typescript-eslint/no-unused-vars': [
        'warn',
        { argsIgnorePattern: '^_', varsIgnorePattern: '^_', caughtErrorsIgnorePattern: '^_' },
      ],
      '@next/next/no-html-link-for-pages': 'off',
    },
  },
  {
    // Tests are allowed to be looser: they poke at the database's shape directly.
    files: ['tests/**/*.{ts,tsx}'],
    rules: {
      '@typescript-eslint/no-explicit-any': 'off',
      '@typescript-eslint/no-non-null-assertion': 'off',
    },
  },
];
