-- LC Housing real-estate job example
-- Created by LC
-- QBCore: add this entry inside QBShared.Jobs in qb-core/shared/jobs.lua.
-- QBox/QBX: register an equivalent job using the method supported by your version.
-- If a realestate job already exists, merge the grades instead of creating a duplicate.

['realestate'] = {
    label = 'Real Estate',
    defaultDuty = true,
    offDutyPay = false,
    grades = {
        ['0'] = { name = 'Trainee Agent', payment = 100 },
        ['1'] = { name = 'Property Agent', payment = 150 },
        ['2'] = { name = 'Senior Agent', payment = 200 },
        ['3'] = { name = 'Broker', payment = 275 },
        ['4'] = { name = 'Managing Broker', isboss = true, payment = 350 }
    }
},
