import crypto from 'node:crypto';
import { Prisma, PrismaClient } from '@prisma/client';
import { hashSync } from '@node-rs/bcrypt';

const SALT_ROUNDS = 12;
const FANCY_ALPHABET = 'abcdefhiklmnorstuvwxyz';

const prisma = new PrismaClient();

const fancyId = (length = 16) => {
  const bytes = crypto.randomBytes(length);
  let out = '';
  for (let i = 0; i < length; i += 1) {
    out += FANCY_ALPHABET[bytes[i] % FANCY_ALPHABET.length];
  }
  return out;
};

const prefixedId = (prefix) => `${prefix}_${fancyId(16)}`;

const DEFAULT_DOCUMENT_EMAIL_SETTINGS = {
  recipientSigningRequest: true,
  recipientRemoved: true,
  recipientSigned: true,
  documentPending: true,
  documentCompleted: true,
  documentDeleted: true,
  ownerDocumentCompleted: true,
  ownerRecipientExpired: true,
  ownerDocumentCreated: true,
};

const generateDefaultOrganisationSettings = () => ({
  documentVisibility: 'EVERYONE',
  documentLanguage: 'en',
  documentTimezone: null,
  documentDateFormat: 'yyyy-MM-dd hh:mm a',
  delegateDocumentOwnership: false,
  includeSenderDetails: true,
  includeSigningCertificate: true,
  includeAuditLog: false,
  typedSignatureEnabled: true,
  uploadSignatureEnabled: true,
  drawSignatureEnabled: true,
  brandingEnabled: false,
  brandingLogo: '',
  brandingUrl: '',
  brandingCompanyDetails: '',
  brandingColors: null,
  brandingCss: '',
  emailId: null,
  emailReplyTo: null,
  emailDocumentSettings: DEFAULT_DOCUMENT_EMAIL_SETTINGS,
  envelopeExpirationPeriod: { unit: 'month', amount: 3 },
  reminderSettings: { sendAfter: { unit: 'day', amount: 5 }, repeatEvery: { unit: 'day', amount: 2 } },
  aiFeaturesEnabled: false,
});

const generateDefaultTeamSettings = () => ({
  documentVisibility: null,
  documentLanguage: null,
  documentTimezone: null,
  documentDateFormat: null,
  delegateDocumentOwnership: null,
  includeSenderDetails: null,
  includeSigningCertificate: null,
  includeAuditLog: null,
  typedSignatureEnabled: null,
  uploadSignatureEnabled: null,
  drawSignatureEnabled: null,
  brandingEnabled: null,
  brandingLogo: null,
  brandingUrl: null,
  brandingCompanyDetails: null,
  brandingColors: null,
  brandingCss: null,
  emailDocumentSettings: null,
  emailId: null,
  emailReplyTo: null,
  envelopeExpirationPeriod: null,
  reminderSettings: null,
  aiFeaturesEnabled: null,
});

const ORGANISATION_INTERNAL_GROUPS = [
  { organisationRole: 'ADMIN', type: 'INTERNAL_ORGANISATION' },
  { organisationRole: 'MANAGER', type: 'INTERNAL_ORGANISATION' },
  { organisationRole: 'MEMBER', type: 'INTERNAL_ORGANISATION' },
];

const TEAM_INTERNAL_GROUPS = [
  { teamRole: 'ADMIN', type: 'INTERNAL_TEAM' },
  { teamRole: 'MANAGER', type: 'INTERNAL_TEAM' },
  { teamRole: 'MEMBER', type: 'INTERNAL_TEAM' },
];

const createOrganisationClaimUpsertData = (claim) => ({
  flags: { ...claim.flags },
  envelopeItemCount: claim.envelopeItemCount,
  recipientCount: claim.recipientCount,
  teamCount: claim.teamCount,
  memberCount: claim.memberCount,
  documentRateLimits: claim.documentRateLimits ?? [],
  documentQuota: claim.documentQuota,
  emailRateLimits: claim.emailRateLimits ?? [],
  emailQuota: claim.emailQuota,
  apiRateLimits: claim.apiRateLimits ?? [],
  apiQuota: claim.apiQuota,
  emailTransportId: claim.emailTransportId ?? null,
});

const ensureFreeClaim = async () => {
  const existing = await prisma.subscriptionClaim.findUnique({
    where: { id: 'free' },
  });

  if (existing) {
    return existing;
  }

  return prisma.subscriptionClaim.create({
    data: {
      id: 'free',
      name: 'Free',
      locked: false,
      teamCount: 1,
      memberCount: 1,
      envelopeItemCount: 5,
      recipientCount: 20,
      flags: {},
      documentRateLimits: [],
      documentQuota: null,
      emailRateLimits: [],
      emailQuota: null,
      apiRateLimits: [],
      apiQuota: null,
      emailTransportId: null,
    },
  });
};

const createOrganisation = async ({ userId, name, type, url, claim }) => {
  const organisationSetting = await prisma.organisationGlobalSettings.create({
    data: {
      ...generateDefaultOrganisationSettings(),
      defaultRecipients: Prisma.DbNull,
      id: prefixedId('org_setting'),
    },
  });

  const organisationClaim = await prisma.organisationClaim.create({
    data: {
      id: prefixedId('org_claim'),
      originalSubscriptionClaimId: claim.id,
      ...createOrganisationClaimUpsertData(claim),
    },
  });

  const organisationAuthenticationPortal = await prisma.organisationAuthenticationPortal.create({
    data: {
      id: prefixedId('org_sso'),
      enabled: false,
      clientId: '',
      clientSecret: '',
      wellKnownUrl: '',
    },
  });

  const orgIdAndUrl = prefixedId('org');

  const organisation = await prisma.organisation.create({
    data: {
      id: orgIdAndUrl,
      name,
      type,
      url: url || orgIdAndUrl,
      ownerUserId: userId,
      organisationGlobalSettingsId: organisationSetting.id,
      organisationClaimId: organisationClaim.id,
      organisationAuthenticationPortalId: organisationAuthenticationPortal.id,
      groups: {
        create: ORGANISATION_INTERNAL_GROUPS.map((group) => ({
          ...group,
          id: prefixedId('org_group'),
        })),
      },
      customerId: null,
    },
    include: {
      groups: true,
    },
  });

  const adminGroup = organisation.groups.find((group) => group.organisationRole === 'ADMIN');

  if (!adminGroup) {
    throw new Error('Admin group not found');
  }

  await prisma.organisationMember.create({
    data: {
      id: prefixedId('member'),
      userId,
      organisationId: organisation.id,
      organisationGroupMembers: {
        create: {
          id: prefixedId('group_member'),
          groupId: adminGroup.id,
        },
      },
    },
  });

  return organisation;
};

const createTeam = async ({ userId, teamName, teamUrl, organisationId }) => {
  const organisation = await prisma.organisation.findFirst({
    where: {
      id: organisationId,
      members: { some: { userId } },
    },
    include: { groups: true },
  });

  if (!organisation) {
    throw new Error('Organisation not found');
  }

  const internalOrganisationGroups = organisation.groups
    .filter((group) => group.type === 'INTERNAL_ORGANISATION')
    .map((group) => ({
      organisationGroupId: group.id,
      teamRole: group.organisationRole === 'MEMBER' ? 'MEMBER' : 'ADMIN',
    }));

  await prisma.$transaction(async (tx) => {
    const teamSettings = await tx.teamGlobalSettings.create({
      data: {
        ...generateDefaultTeamSettings(),
        defaultRecipients: Prisma.DbNull,
        id: prefixedId('team_setting'),
      },
    });

    const team = await tx.team.create({
      data: {
        name: teamName,
        url: teamUrl,
        organisationId,
        teamGlobalSettingsId: teamSettings.id,
        teamGroups: {
          createMany: {
            data: internalOrganisationGroups.map((group) => ({
              ...group,
              id: prefixedId('team_group'),
            })),
          },
        },
      },
    });

    for (const teamGroup of TEAM_INTERNAL_GROUPS) {
      await tx.organisationGroup.create({
        data: {
          id: prefixedId('org_group'),
          type: teamGroup.type,
          organisationRole: 'MEMBER',
          organisationId,
          teamGroups: {
            create: {
              id: prefixedId('team_group'),
              teamId: team.id,
              teamRole: teamGroup.teamRole,
            },
          },
        },
      });
    }
  });
};

const ensureAdmin = async ({ email, password }) => {
  const hashedPassword = hashSync(password, SALT_ROUNDS);
  const normalizedEmail = email.toLowerCase();

  const existing = await prisma.user.findFirst({
    where: { email: normalizedEmail },
  });

  const user = await prisma.user.upsert({
    where: { email: normalizedEmail },
    update: {
      password: hashedPassword,
      emailVerified: existing?.emailVerified ?? new Date(),
      roles: ['USER', 'ADMIN'],
      disabled: false,
    },
    create: {
      name: 'Administrator',
      email: normalizedEmail,
      password: hashedPassword,
      emailVerified: new Date(),
      roles: ['USER', 'ADMIN'],
      disabled: false,
    },
  });

  const existingOrganisation = await prisma.organisation.findFirst({
    where: { ownerUserId: user.id },
  });

  if (!existingOrganisation) {
    const freeClaim = await ensureFreeClaim();

    const organisation = await createOrganisation({
      userId: user.id,
      name: 'Personal Organisation',
      type: 'PERSONAL',
      url: undefined,
      claim: freeClaim,
    });

    await createTeam({
      userId: user.id,
      teamName: 'Personal Team',
      teamUrl: prefixedId('personal'),
      organisationId: organisation.id,
    });
  }

  return user;
};

const main = async () => {
  const email = process.env.DOCUMENSO_ADMIN_EMAIL;
  const password = process.env.DOCUMENSO_ADMIN_PASSWORD;

  if (!email || !password) {
    throw new Error('DOCUMENSO_ADMIN_EMAIL and DOCUMENSO_ADMIN_PASSWORD must be set');
  }

  await ensureFreeClaim();
  await ensureAdmin({ email, password });

  console.log('Seed complete');
};

main()
  .catch((err) => {
    console.error(err);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
