# TasteTrace - Food & Symptom Tracking Application

## Overview

TasteTrace is a full-stack web application designed to help users track their meals and symptoms to identify potential correlations between food consumption and health symptoms. The application provides an intuitive interface for logging meals and symptoms, analyzing patterns, and generating insights about potential food triggers.

## System Architecture

### Frontend Architecture
- **Framework**: React 18 with TypeScript
- **Styling**: Tailwind CSS with shadcn/ui component library
- **State Management**: TanStack Query (React Query) for server state management
- **Routing**: Wouter for client-side routing
- **Build Tool**: Vite for fast development and optimized production builds
- **Form Handling**: React Hook Form with Zod validation

### Backend Architecture
- **Runtime**: Node.js with Express.js framework
- **Language**: TypeScript (ESM modules)
- **API Style**: RESTful API endpoints
- **Authentication**: Replit Auth with OpenID Connect
- **Session Management**: Express sessions with PostgreSQL storage

### Database Architecture
- **Database**: PostgreSQL (via Neon serverless)
- **ORM**: Drizzle ORM with Drizzle Kit for migrations
- **Connection**: Neon serverless driver with WebSocket support
- **Schema**: Well-defined relational schema with proper indexing

## Key Components

### Database Schema
- **Users**: Stores user profile information from Replit Auth
- **Sessions**: Manages user authentication sessions
- **Meals**: Records food consumption with dietary tags and ingredients
- **Symptoms**: Tracks health symptoms with severity levels
- **Correlations**: Stores calculated food-symptom relationships (implied from code structure)

### API Endpoints
- `/api/meals` - CRUD operations for meal tracking
- `/api/symptoms` - CRUD operations for symptom tracking
- `/api/correlations` - Food-symptom correlation analysis
- `/api/auth/*` - Authentication and user management
- `/api/entries/recent` - Recent activity dashboard data
- `/api/stats/monthly` - Monthly statistics for insights

### UI Components
- **shadcn/ui**: Complete component library for consistent design
- **Custom Components**: Specialized meal and symptom tracking forms
- **Dashboard**: Real-time insights and recent activity overview
- **Calendar**: Historical data visualization
- **Charts**: Data visualization for correlations and trends

## Data Flow

1. **User Authentication**: Replit Auth handles user login/logout
2. **Data Entry**: Users log meals and symptoms through intuitive forms
3. **Storage**: Data is validated and stored in PostgreSQL via Drizzle ORM
4. **Analysis**: Backend calculates correlations between foods and symptoms
5. **Visualization**: Frontend displays insights through charts and dashboards
6. **Real-time Updates**: TanStack Query manages cache invalidation and updates

## External Dependencies

### Core Dependencies
- **@neondatabase/serverless**: PostgreSQL database connection
- **drizzle-orm & drizzle-kit**: Database ORM and migrations
- **@tanstack/react-query**: Server state management
- **wouter**: Lightweight React router
- **react-hook-form**: Form validation and handling
- **@radix-ui/***: Accessible UI primitives for shadcn/ui

### Development Tools
- **Vite**: Fast build tool with HMR
- **TypeScript**: Type safety across the stack
- **Tailwind CSS**: Utility-first CSS framework
- **ESBuild**: Production bundling for server code

### Authentication & Security
- **openid-client**: OIDC authentication with Replit
- **express-session**: Session management
- **connect-pg-simple**: PostgreSQL session storage

## Deployment Strategy

### Development Environment
- **Platform**: Replit with Node.js 20 runtime
- **Database**: PostgreSQL 16 module
- **Hot Reload**: Vite development server with HMR
- **Process**: `npm run dev` starts both frontend and backend

### Production Build
- **Frontend**: Vite builds optimized static assets
- **Backend**: ESBuild bundles server code with external packages
- **Deployment**: Replit autoscale deployment target
- **Port Configuration**: Internal port 5000, external port 80

### Environment Configuration
- **Database**: Requires `DATABASE_URL` environment variable
- **Authentication**: Requires Replit-specific environment variables
- **Sessions**: Requires `SESSION_SECRET` for secure sessions

## User Preferences

Preferred communication style: Simple, everyday language.

## Changelog

Changelog:
- June 20, 2025. Initial setup
- June 26, 2025. Implemented email/password authentication system with user profiles, secure session management, and user-specific data isolation
- July 12, 2025. Implemented all UX improvements: multiple meal tile selection with navy highlighting, password error messages, updated symptom categories (general stomachache, joint/muscle pain), redesigned insights page with symptoms as headers, and added forgot password functionality
- July 12, 2025. Enhanced correlation analysis with intelligent food parsing: automatically breaks down combined meals into individual ingredients while preserving compound foods like "Avocado Toast" and "Salad". Fixed history page to show unique symptoms per day and filtered insights to display only individual ingredients for clearer correlation analysis.