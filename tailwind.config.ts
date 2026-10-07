
import type { Config } from "tailwindcss";
import plugin from "tailwindcss/plugin";

export default {
	darkMode: ["class"],
	content: [
		"./pages/**/*.{ts,tsx}",
		"./components/**/*.{ts,tsx}",
		"./app/**/*.{ts,tsx}",
		"./src/**/*.{ts,tsx}",
	],
	prefix: "",
	theme: {
		container: {
			center: true,
			padding: '2rem',
			screens: {
				'2xl': '1400px'
			}
		},
    extend: {
      fontFamily: {
        'inter': ['Inter', 'sans-serif'],
        // The app typeface (DESIGN.md): one family, weights do the serif/sans work
        'montreal': ['PP Neue Montreal', 'Inter', '-apple-system', 'sans-serif'],
        'editorial': ['PPEditorialNew-Regular', 'serif'],
        'editorial-italic': ['PPEditorialNew-Italic', 'serif'],
        'mori': ['PPMori-Regular', 'sans-serif'],
        'tobias': ['Tobias', 'serif'],
        // DESIGN-v2's machine voice; only at text-pixel / -md / -lg (11 / 16.5 / 22 px)
        'pixel': ['"Departure Mono"', 'ui-monospace', '"SF Mono"', 'Menlo', 'monospace'],
        // DESIGN-v2's code voice: literal strings (URLs, commands, code) and the decrypt cipher
        'code': ['"JetBrains Mono"', 'ui-monospace', '"SF Mono"', 'Menlo', 'monospace'],
      },
      // DESIGN-v2 type: the product scale (Montreal) and Departure Mono's three sizes
      fontSize: {
        'pixel': ['11px', { lineHeight: '1.45', letterSpacing: '0' }],
        'pixel-md': ['16.5px', { lineHeight: '1.3', letterSpacing: '0' }],
        'pixel-lg': ['22px', { lineHeight: '1.2', letterSpacing: '0' }],
        'screen-title': ['28px', { lineHeight: '1.1', letterSpacing: '-0.03em' }],
        'section-title': ['20px', { lineHeight: '1.2', letterSpacing: '-0.02em' }],
        'object-title': ['18px', { lineHeight: '1.2', letterSpacing: '-0.018em' }],
        'body': ['15px', { lineHeight: '1.45', letterSpacing: '-0.005em' }],
        'label': ['13px', { lineHeight: '1.3', letterSpacing: '0' }],
      },
			colors: {
				// DESIGN-v2 print palette (src/index.css :root). The spot is a variable (lime by
				// default, violet as the alternative) so it carries Tailwind's alpha modifier.
				// paper and ink carry channels too, so opacity modifiers (text-ink/80, bg-paper/80) compile
				paper: 'rgb(var(--paper-rgb) / <alpha-value>)',
				ink: {
					DEFAULT: 'rgb(var(--ink-rgb) / <alpha-value>)',
					soft: 'var(--ink-soft)',
					muted: 'var(--ink-muted)',
				},
				line: {
					DEFAULT: 'var(--line)',
					soft: 'var(--line-soft)',
				},
				fill: 'var(--fill)',
				spot: {
					DEFAULT: 'rgb(var(--spot-rgb) / <alpha-value>)',
					on: 'var(--on-spot)',
					ink: 'var(--spot-ink)',
					'on-ink': 'var(--spot-on-ink)',
				},
				ok: 'var(--ok)',
				error: 'var(--error)',
				border: 'hsl(var(--border))',
				input: 'hsl(var(--input))',
				ring: 'hsl(var(--ring))',
				background: 'hsl(var(--background))',
				foreground: 'hsl(var(--foreground))',
				primary: {
					DEFAULT: 'hsl(var(--primary))',
					foreground: 'hsl(var(--primary-foreground))'
				},
				secondary: {
					DEFAULT: 'hsl(var(--secondary))',
					foreground: 'hsl(var(--secondary-foreground))'
				},
				destructive: {
					DEFAULT: 'hsl(var(--destructive))',
					foreground: 'hsl(var(--destructive-foreground))'
				},
				muted: {
					DEFAULT: 'hsl(var(--muted))',
					foreground: 'hsl(var(--muted-foreground))'
				},
				accent: {
					DEFAULT: 'hsl(var(--accent))',
					foreground: 'hsl(var(--accent-foreground))'
				},
				popover: {
					DEFAULT: 'hsl(var(--popover))',
					foreground: 'hsl(var(--popover-foreground))'
				},
				card: {
					DEFAULT: 'hsl(var(--card))',
					foreground: 'hsl(var(--card-foreground))'
				},
				sidebar: {
					DEFAULT: 'hsl(var(--sidebar-background))',
					foreground: 'hsl(var(--sidebar-foreground))',
					primary: 'hsl(var(--sidebar-primary))',
					'primary-foreground': 'hsl(var(--sidebar-primary-foreground))',
					accent: 'hsl(var(--sidebar-accent))',
					'accent-foreground': 'hsl(var(--sidebar-accent-foreground))',
					border: 'hsl(var(--sidebar-border))',
					ring: 'hsl(var(--sidebar-ring))'
				}
			},
			borderRadius: {
				lg: 'var(--radius)',
				md: 'calc(var(--radius) - 2px)',
				sm: 'calc(var(--radius) - 4px)',
				// DESIGN-v2: objects (cards, sheets, the composer) are near-square; machine is 0
				object: '2px',
			},
			boxShadow: {
				// DESIGN-v2 elevation: an object sits on the paper; hovered, it lifts onto a hard
				// print shadow (the retro beat); sheets and drawings get the long soft one
				object: '0 1px 0 rgba(20, 22, 18, 0.04), 0 10px 24px -18px rgba(20, 22, 18, 0.28)',
				print: '4px 4px 0 0 var(--ink)',
				'print-sm': '2px 2px 0 0 var(--ink)',
				drawing: '0 30px 60px -36px rgba(0, 0, 0, 0.45)',
			},
			transitionTimingFunction: {
				'v2': 'cubic-bezier(0.22, 1, 0.36, 1)',
				'pop': 'cubic-bezier(0.34, 1.56, 0.64, 1)',
			},
			keyframes: {
				'accordion-down': {
					from: {
						height: '0'
					},
					to: {
						height: 'var(--radix-accordion-content-height)'
					}
				},
				'accordion-up': {
					from: {
						height: 'var(--radix-accordion-content-height)'
					},
					to: {
						height: '0'
					}
				},
				'fadeIn': {
					'0%': {
						opacity: '0',
						transform: 'translateY(20px)'
					},
					'100%': {
						opacity: '1',
						transform: 'translateY(0)'
					}
				},
				'slideUp': {
					'0%': {
						opacity: '0',
						transform: 'translateY(30px)'
					},
					'100%': {
						opacity: '1',
						transform: 'translateY(0)'
					}
				}
			},
			animation: {
				'accordion-down': 'accordion-down 0.2s ease-out',
				'accordion-up': 'accordion-up 0.2s ease-out',
				'fadeIn': 'fadeIn 0.6s ease-out forwards',
				'slideUp': 'slideUp 0.8s ease-out forwards'
			}
		}
	},
	plugins: [
		require("tailwindcss-animate"),
		require("@tailwindcss/typography"),
		// `v2:` styles shared primitives (shadcn ui/*) only where <html data-ui="v2">, so
		// marketing and auth pages that use the same components keep their v1 look
		plugin(({ addVariant }) => {
			addVariant('v2', '[data-ui="v2"] &');
		}),
	],
} satisfies Config;
