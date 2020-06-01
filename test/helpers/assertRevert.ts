const should = require('chai').should()

export default async function assertRevert<T>(promise: Promise<T>, message?: string) {
  try {
    await promise
  } catch (error) {
    error.message.should.include(
      message
        ? `VM Exception while processing transaction: revert ${message}`
        : 'revert',
      `Expected "revert", got ${error} instead`
    )
    return
  }
  should.fail('Expected revert not received')
}
